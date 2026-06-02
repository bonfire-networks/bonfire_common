defmodule Bonfire.Common.Telemetry.LoadTestCapture do
  @moduledoc """
  On-demand, in-memory capture of ONLY slow DB queries, slow connection
  checkouts (pool wait), and slow HTTP requests — for load testing without
  drowning in Bonfire's normal logs.

  Nothing is logged: matching events are stored in a bounded ETS ring buffer
  and are queried afterwards (from a remote console / Tidewave):

      alias Bonfire.Common.Telemetry.LoadTestCapture, as: Cap
      Cap.enable(); Cap.reset()    # before the load test
      # ...run the test...
      Cap.summary()                # pool-wait vs slow-query vs request verdict
      Cap.worst_by_queue(20)       # top pool-wait events  -> pool starvation?
      Cap.worst_by_query(20)       # top slow queries (parameterised SQL + stacktrace)
      Cap.worst_requests(20)       # slowest SERVER-SIDE requests -> server vs harness
      Cap.disable()

  Why three dimensions: high `queue_time` means the pool was starved (requests
  waiting for a connection), high `query_time` means a query itself was slow
  (bad plan / missing index / lock), and the server-side request duration tells
  us whether a client-observed stall actually happened on the server at all (vs
  in the load generator / network path).

  It is self-starting (no supervision-tree changes) and removable: it only
  attaches telemetry handlers while enabled and writes to its own ETS table.
  """
  use GenServer

  @table __MODULE__

  ## Public API

  @doc "Attach telemetry handlers and start capturing. Thresholds (ms) are overridable."
  def enable(opts \\ []) do
    ensure_started()
    GenServer.call(__MODULE__, {:enable, Map.merge(defaults(), Map.new(opts))})
  end

  @doc "Detach handlers and stop capturing (already-captured data stays queryable)."
  def disable, do: GenServer.call(__MODULE__, :disable)

  @doc "Clear all captured events."
  def reset do
    ensure_started()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp defaults, do: %{query_ms: 200, queue_ms: 30, request_ms: 1_000, max: 5_000}

  defp ensure_started do
    case start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, %{enabled: false}}
  end

  @impl true
  def handle_call({:enable, th}, _from, state) do
    :persistent_term.put({@table, :th}, th)

    unless state.enabled do
      query_event = repo_query_event()
      :telemetry.attach("loadtest-db", query_event, &__MODULE__.on_query/4, nil)

      :telemetry.attach(
        "loadtest-req",
        [:phoenix, :endpoint, :stop],
        &__MODULE__.on_request/4,
        nil
      )
    end

    {:reply, :ok, %{state | enabled: true}}
  end

  def handle_call(:disable, _from, state) do
    :telemetry.detach("loadtest-db")
    :telemetry.detach("loadtest-req")
    {:reply, :ok, %{state | enabled: false}}
  end

  # Derive the repo's telemetry prefix rather than hardcoding it
  defp repo_query_event do
    prefix =
      try do
        Bonfire.Common.Repo.config()[:telemetry_prefix] || [:bonfire, :repo]
      rescue
        _ -> [:bonfire, :repo]
      end

    prefix ++ [:query]
  end

  ## Hot-path handlers (run in the caller process; direct ETS write, no GenServer call)

  def on_query(_event, measurements, metadata, _config) do
    th = th()
    query_ms = ms(measurements[:query_time]) + ms(measurements[:decode_time])
    queue_ms = ms(measurements[:queue_time])

    if queue_ms >= th.queue_ms or query_ms >= th.query_ms do
      put(th, %{
        kind: :db,
        total_ms: query_ms,
        queue_ms: queue_ms,
        source: metadata[:source],
        sql: metadata[:query] |> to_string() |> String.slice(0, 300),
        stack: format_stack(metadata[:stacktrace])
      })
    end
  end

  def on_request(_event, measurements, metadata, _config) do
    th = th()
    dur = ms(measurements[:duration])

    if dur >= th.request_ms do
      conn = metadata[:conn]

      put(th, %{
        kind: :request,
        total_ms: dur,
        path: conn && conn.request_path,
        method: conn && conn.method,
        status: conn && conn.status
      })
    end
  end

  defp put(th, rec) do
    seq = :ets.update_counter(@table, :__seq__, {2, 1}, {:__seq__, 0})
    :ets.insert(@table, {rem(seq, th.max), rec})
  end

  ## Queries (cold path)

  @doc "At-a-glance verdict: pool-wait vs slow-query vs server-side request time."
  def summary do
    db = recs(:db)
    reqs = recs(:request)

    %{
      db_events: length(db),
      requests: length(reqs),
      queue_wait_ms: pct(Enum.map(db, & &1.queue_ms)),
      query_time_ms: pct(Enum.map(db, & &1.total_ms)),
      request_ms: pct(Enum.map(reqs, & &1.total_ms)),
      queue_dominated: Enum.count(db, &(&1.queue_ms > &1.total_ms))
    }
  end

  def worst_by_queue(n \\ 20), do: top(recs(:db), & &1.queue_ms, n)
  def worst_by_query(n \\ 20), do: top(recs(:db), & &1.total_ms, n)
  def worst_requests(n \\ 20), do: top(recs(:request), & &1.total_ms, n)

  defp recs(kind),
    do: for({k, v} <- :ets.tab2list(@table), is_integer(k), v.kind == kind, do: v)

  defp top(list, by, n), do: list |> Enum.sort_by(by, :desc) |> Enum.take(n)

  defp pct([]), do: %{p50: 0.0, p95: 0.0, max: 0.0}

  defp pct(xs) do
    sorted = Enum.sort(xs)
    len = length(sorted)
    %{p50: at(sorted, div(len, 2)), p95: at(sorted, trunc(len * 0.95)), max: List.last(sorted)}
  end

  defp at(list, i), do: Enum.at(list, min(i, length(list) - 1))

  defp ms(nil), do: 0.0
  defp ms(t), do: System.convert_time_unit(t, :native, :microsecond) / 1000

  defp th, do: :persistent_term.get({@table, :th}, defaults())

  defp format_stack(nil), do: nil
  defp format_stack(st), do: st |> Enum.take(3) |> Enum.map_join(" <- ", &inspect/1)
end
