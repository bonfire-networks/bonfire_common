defmodule Bonfire.Common.Telemetry.StormRecorder do
  @moduledoc """
  On-demand storm attribution recorder. Start it right before a load experiment (e.g. posting from a many-followers account), it snapshots system state every `interval_ms` into a bounded in-memory ring, auto-stops after its window, and `dump/1` prints a paste-able summary and returns the raw snapshots. Zero cost when not running: the telemetry handlers attach on `start` and DETACH on stop, nothing is measured between runs.

      StormRecorder.start(minutes: 60)
      # ... trigger the storm ...
      StormRecorder.dump()

  Caller-class attribution relies on the `Logger.metadata(caller_class: ...)` convention (e.g. `:ap | :web | :oban`, NOT a fixed list; classes are whatever the plugs/hooks declare) set by the AP/browser pipeline plugs and the Oban job-start hook; the AP workers' existing `Logger.metadata(action: op)` is picked up as a second dimension. Logger metadata lives in the pdict (`:"$logger_metadata$"`), so one call tags both log lines and telemetry, and `ProcessTree` reads let spawned Tasks inherit their origin's class. Unmarked processes count as `:unknown` (a large `:unknown` share is itself a finding).
  """
  use GenServer
  use Bonfire.Common.Config
  require Logger
  alias Bonfire.Common.Repo

  @tab __MODULE__.Counters
  @handler_id "storm-recorder"
  @max_shapes 200
  @top_n 5

  # ── API ──────────────────────────────────────────────────────────

  def start(opts \\ []) do
    _ = stop()
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      pid -> GenServer.stop(pid, :normal, 10_000)
    end
  end

  def status, do: call(:status)
  def dump(opts \\ []), do: call({:dump, opts})

  defp call(msg) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, msg, 30_000)
    end
  end

  # ── lifecycle ────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    interval = opts[:interval_ms] || 15_000
    minutes = opts[:minutes] || 60
    auto_stop_ms = opts[:auto_stop_ms] || minutes * 60_000
    max_entries = opts[:max_entries] || max(div(auto_stop_ms, interval), 1)

    :ets.new(@tab, [:named_table, :public, :set, write_concurrency: true])
    attach_handlers()
    # scheduler_wall_time must be on for :scheduler.sample/0; guarded — never block start
    safe(fn -> :erlang.system_flag(:scheduler_wall_time, true) end)

    Process.send_after(self(), :auto_stop, auto_stop_ms)
    {:ok, _} = :timer.send_interval(interval, :tick)

    {:ok,
     %{
       ring: :queue.new(),
       count: 0,
       max: max_entries,
       interval: interval,
       started_at: DateTime.utc_now(),
       last_sched_sample: safe(fn -> :scheduler.sample() end),
       pgss_start: pg_stat_statements_top()
     }}
  end

  @impl true
  def terminate(_reason, state) do
    detach_handlers()
    log_pgss_diff(state)
    :ok
  end

  @impl true
  def handle_info(:auto_stop, state), do: {:stop, :normal, state}

  def handle_info(:tick, state) do
    {util, state} = take_scheduler_sample(state)

    ring = :queue.in(snapshot(util), state.ring)

    {ring, count} =
      if state.count >= state.max,
        do: {elem(:queue.out(ring), 1), state.count},
        else: {ring, state.count + 1}

    {:noreply, %{state | ring: ring, count: count}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:count, :max, :interval, :started_at]), state}
  end

  def handle_call({:dump, opts}, _from, state) do
    entries = :queue.to_list(state.ring) |> maybe_last(opts[:last])
    render(entries)
    {:reply, entries, state}
  end

  # ── telemetry handlers (attach on start, detach on stop) ────────

  defp attach_handlers do
    :telemetry.attach_many(
      @handler_id,
      [
        repo_query_event(),
        [:phoenix, :router_dispatch, :stop],
        [:finch, :request, :stop]
      ],
      &__MODULE__.handle_event/4,
      %{repo_query_event: repo_query_event()}
    )
  end

  defp detach_handlers, do: :telemetry.detach(@handler_id)

  defp repo_query_event do
    (Repo.config()[:telemetry_prefix] || [:bonfire, :common, :repo]) ++ [:query]
  end

  @doc false
  # Runs in the CALLING process — counter bumps only, and it must NEVER take the caller down.
  def handle_event(event, measurements, meta, config) do
    cond do
      event == config[:repo_query_event] ->
        {class, action} = context()
        bump({:db, class, :count}, 1)
        bump({:db, class, :queue_us}, native_us(measurements[:queue_time]))
        bump_max({:db, class, :queue_max_us}, native_us(measurements[:queue_time]))
        bump({:db, class, :query_us}, native_us(measurements[:query_time]))

        if action do
          bump({:act, action, :count}, 1)

          bump(
            {:act, action, :us},
            native_us(measurements[:total_time] || measurements[:query_time])
          )
        end

        shape_bump(
          meta[:query],
          native_us(measurements[:total_time] || measurements[:query_time])
        )

      event == [:phoenix, :router_dispatch, :stop] ->
        route = meta[:route] || "unknown"
        {class, _action} = context()
        bump({:req, class, route, :count}, 1)
        bump({:req, class, route, :us}, native_us(measurements[:duration]))

      event == [:finch, :request, :stop] ->
        bump({:out, :count}, 1)
        bump({:out, :us}, native_us(measurements[:duration]))

      true ->
        :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp context do
    # The marker convention is `Logger.metadata(caller_class: ...)` — Logger metadata lives in
    # the pdict under :"$logger_metadata$", so one call both tags every log line the process
    # emits AND makes the class readable here. Classes are NOT a fixed list (traffic classes
    # and `action:` values are set by code across extensions/forks — e.g. the AP workers'
    # existing `Logger.metadata(action: op)`); anything atom-or-short-string is accepted,
    # sanitize only by type. ProcessTree walks ancestors, so work spawned in Tasks by a
    # request/job still attributes to its origin. Caveat: inheritance finds the NEAREST
    # ancestor with any logger metadata — an intermediate process that set unrelated metadata
    # (without these keys) stops the walk (→ :unknown).
    case ProcessTree.get(:"$logger_metadata$") do
      %{} = md -> {sanitize(md[:caller_class]) || :unknown, sanitize(md[:action])}
      _ -> {:unknown, nil}
    end
  end

  defp sanitize(value) when is_atom(value) and not is_nil(value), do: value
  defp sanitize(value) when is_binary(value), do: String.slice(value, 0, 60)
  defp sanitize(_), do: nil

  defp native_us(nil), do: 0
  defp native_us(v) when is_integer(v), do: System.convert_time_unit(v, :native, :microsecond)
  defp native_us(_), do: 0

  defp bump(key, by) do
    :ets.update_counter(@tab, key, by, {key, 0})
  end

  defp bump_max(key, value) do
    case :ets.lookup(@tab, key) do
      [{^key, current}] when current >= value -> :ok
      _ -> :ets.insert(@tab, {key, value})
    end
  end

  defp shape_bump(query, us) when is_binary(query) do
    key = {:shape, query}

    cond do
      :ets.member(@tab, {key, :count}) ->
        bump_shape(key, us)

      shape_count() < @max_shapes ->
        :ets.update_counter(@tab, :shape_count, 1, {:shape_count, 0})
        bump_shape(key, us)

      true ->
        bump_shape({:shape, :overflow}, us)
    end
  end

  defp shape_bump(_, _), do: :ok

  defp bump_shape({:shape, _} = key, us) do
    :ets.update_counter(@tab, {key, :count}, 1, {{key, :count}, 0})
    :ets.update_counter(@tab, {key, :us}, us, {{key, :us}, 0})
    :ok
  end

  defp shape_count do
    :ets.update_counter(@tab, :shape_count, 0, {:shape_count, 0})
  rescue
    _ -> 0
  end

  # ── per-tick snapshot ────────────────────────────────────────────

  defp snapshot(sched_util) do
    %{
      at: DateTime.utc_now(),
      run_queue: safe(fn -> :erlang.statistics(:total_run_queue_lengths_all) end) || 0,
      schedulers: System.schedulers_online(),
      sched_util: sched_util,
      memory: :erlang.memory() |> Map.new() |> Map.take([:total, :processes, :binary]),
      db: drain_db(),
      actions: drain_actions(),
      top_shapes: drain_shapes(),
      requests: drain_requests(),
      outbound: drain_outbound(),
      pg: guarded(&pg_activity_summary/0),
      oban: guarded(&oban_depths/0),
      caches: cachex_stats()
    }
  end

  defp drain_db do
    # classes are dynamic (whatever caller_class metadata carried this tick)
    :ets.match(@tab, {{:db, :"$1", :count}, :"$2"})
    |> Map.new(fn [class, count] ->
      :ets.delete(@tab, {:db, class, :count})

      {class,
       %{
         count: count,
         queue_us: take_counter({:db, class, :queue_us}),
         queue_max_us: take_counter({:db, class, :queue_max_us}),
         query_us: take_counter({:db, class, :query_us})
       }}
    end)
  end

  defp drain_actions do
    :ets.match(@tab, {{:act, :"$1", :count}, :"$2"})
    |> Map.new(fn [action, count] ->
      :ets.delete(@tab, {:act, action, :count})
      {action, %{count: count, total_us: take_counter({:act, action, :us})}}
    end)
  end

  defp drain_shapes do
    shapes =
      :ets.match(@tab, {{{:shape, :"$1"}, :count}, :"$2"})
      |> Enum.map(fn [shape, count] ->
        us = take_counter({{:shape, shape}, :us})
        :ets.delete(@tab, {{:shape, shape}, :count})
        %{shape: shape_label(shape), count: count, total_us: us}
      end)

    :ets.insert(@tab, {:shape_count, 0})

    %{
      by_count: shapes |> Enum.sort_by(& &1.count, :desc) |> Enum.take(@top_n),
      by_time: shapes |> Enum.sort_by(& &1.total_us, :desc) |> Enum.take(@top_n)
    }
  end

  defp shape_label(:overflow), do: "(shapes past cap #{@max_shapes})"
  defp shape_label(query), do: String.slice(query, 0, 120)

  defp drain_requests do
    :ets.match(@tab, {{:req, :"$1", :"$2", :count}, :"$3"})
    |> Enum.map(fn [class, route, count] ->
      us = take_counter({:req, class, route, :us})
      :ets.delete(@tab, {:req, class, route, :count})
      %{class: class, route: route, count: count, total_us: us}
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(10)
  end

  defp drain_outbound do
    %{count: take_counter({:out, :count}), total_us: take_counter({:out, :us})}
  end

  defp take_counter(key) do
    case :ets.take(@tab, key) do
      [{^key, value}] -> value
      _ -> 0
    end
  end

  defp guarded(fun) do
    fun.()
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp take_scheduler_sample(state) do
    util =
      case state.last_sched_sample do
        nil ->
          nil

        sample ->
          safe(fn ->
            :scheduler.utilization(sample)
            |> Enum.find_value(fn
              {:total, frac, _} -> Float.round(frac, 3)
              _ -> nil
            end)
          end)
      end

    {util, %{state | last_sched_sample: safe(fn -> :scheduler.sample() end)}}
  end

  # ── external reads (guarded — :unavailable is itself a datum) ────

  defp pg_activity_summary do
    Repo.query!(
      "SELECT state, wait_event_type, count(*) FROM pg_stat_activity WHERE datname = current_database() GROUP BY 1, 2",
      [],
      timeout: 5_000
    ).rows
  end

  defp oban_depths do
    Repo.query!(
      "SELECT queue, state, count(*) FROM oban_jobs WHERE state IN ('available', 'executing', 'retryable') GROUP BY 1, 2",
      [],
      timeout: 5_000
    ).rows
  end

  defp pg_stat_statements_top do
    guarded(fn ->
      Repo.query!(
        "SELECT queryid::text, substring(query, 1, 80), calls, total_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20",
        [],
        timeout: 5_000
      ).rows
    end)
  end

  defp cachex_stats do
    Config.get([__MODULE__, :caches], [])
    |> Map.new(fn cache ->
      {cache,
       guarded(fn ->
         case Cachex.stats(cache) do
           {:ok, stats} -> Map.merge(stats, %{size: elem(Cachex.size(cache), 1)})
           {:error, :stats_disabled} -> :stats_disabled
           _ -> :unavailable
         end
       end)}
    end)
  end

  # ── output ───────────────────────────────────────────────────────

  defp maybe_last(entries, n) when is_integer(n) and n > 0, do: Enum.take(entries, -n)
  defp maybe_last(entries, _), do: entries

  defp render([]), do: IO.puts("StormRecorder: no snapshots yet")

  defp render(entries) do
    IO.puts("\ntime     runq util  mem_mb  db per class (max queue ms)          req top route")

    for s <- entries do
      db =
        s.db
        |> Enum.sort_by(fn {_, %{count: c}} -> -c end)
        |> Enum.map_join(" ", fn {class, %{count: c}} -> "#{class}:#{c}" end)
        |> case do
          "" -> "-"
          str -> str
        end

      max_q =
        s.db
        |> Enum.map(fn {_, stats} -> stats[:queue_max_us] || 0 end)
        |> Enum.max(fn -> 0 end)
        |> div(1000)

      top_req =
        case s.requests do
          [%{route: route, count: count} | _] -> "#{count}× #{route}"
          _ -> "-"
        end

      IO.puts(
        "#{Calendar.strftime(s.at, "%H:%M:%S")} #{String.pad_leading(to_string(s.run_queue), 4)} " <>
          "#{String.pad_leading(to_string(s.sched_util || "-"), 5)} " <>
          "#{String.pad_leading(to_string(div(s.memory.total, 1_048_576)), 6)}  " <>
          "#{String.pad_trailing(db, 24)} (#{max_q}ms)  #{top_req}"
      )
    end

    :ok
  end

  defp log_pgss_diff(%{pgss_start: :unavailable}), do: :ok

  defp log_pgss_diff(%{pgss_start: start_rows}) do
    case pg_stat_statements_top() do
      :unavailable ->
        :ok

      end_rows ->
        started = Map.new(start_rows, fn [id, q, calls, time] -> {id, {q, calls, time}} end)

        diff =
          end_rows
          |> Enum.map(fn [id, q, calls, time] ->
            {_, calls0, time0} = Map.get(started, id, {q, 0, 0.0})
            {q, calls - calls0, time - time0}
          end)
          |> Enum.sort_by(&elem(&1, 2), :desc)
          |> Enum.take(10)

        Logger.info(
          "StormRecorder pg_stat_statements window diff (top by exec time):\n" <>
            Enum.map_join(diff, "\n", fn {q, calls, time} ->
              "  #{Float.round(time * 1.0, 1)}ms over #{calls} calls: #{q}"
            end)
        )
    end
  end
end
