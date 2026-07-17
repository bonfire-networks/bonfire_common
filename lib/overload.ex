defmodule Bonfire.Common.Overload do
  @moduledoc """
  A shared "instance overloaded" signal: one sampler GenServer computes a load level from cheap signals and stores/publishes it, so shedding consumers (the AP 429 plug, the browser fail-whale, etc) all read ONE source of truth and thresholds tune in one place.

  `level/0` is a `:persistent_term` read: consumers on every request pay essentially nothing. One transition point emits to the three output channels (each ~free when unconsumed): the persistent_term snapshot (pull), `[:bonfire, :overload, :sample | :transition | :shed]` telemetry (observation: StormRecorder, dashboards, exporters), and a node-local PubSub broadcast on transitions (process fan-out: NotificationLive banner, storm overlay). Sustained `:hard` additionally raises an OTP alarm, which the existing `Bonfire.Common.Telemetry.SystemMonitor` alarm handler logs and can email.

  Primary signal: BEAM run-queue depth (`:erlang.statistics(:total_run_queue_lengths_all)`): backlog, deliberately not CPU-utilization-percent (100% util with an empty queue is a busy node serving everyone fine). 

  Hysteresis: escalate one level after `up_ticks` consecutive threshold-exceeding samples, de-escalate ONE level after `down_ticks` consecutive clear-for-that-level samples plus a cooldown after any `:hard` episode: get defensive fast, relax slowly, never flap on a single spike.

  Modes (read per tick): 
  - `:monitor` (DEFAULT: computes/publishes levels and would-shed telemetry but `level/0` returns `:ok`, so nothing sheds; observe the false-positive rate before flipping), 
  - `:enforce`, 
  - `:off`. 

  `stand_down/2` temporarily forces `:ok` with auto-expiry (misfires, debugging-under-load), written to the persistent_term immediately, never blocked behind a busy pool.
  """
  use GenServer
  require Logger
  use Bonfire.Common.Config

  @state_key {__MODULE__, :state}

  # ── consumer API (hot path: persistent_term reads only) ───────────────────

  @doc "The effective level consumers act on: `:ok | :soft | :hard` (always `:ok` in `:monitor` mode or during a stand-down)."
  def level do
    state = published()

    cond do
      state[:mode] != :enforce -> :ok
      stand_down_active?(state) -> :ok
      true -> state[:level] || :ok
    end
  end

  @doc "The computed level regardless of mode/stand-down (what `:monitor` mode observes)."
  def raw_level, do: published()[:level] || :ok

  @doc "Adaptive Retry-After seconds — scales with how far past `:hard` the signal is and how long the episode has lasted."
  def retry_after, do: published()[:retry_after] || 30

  @doc "The latest sample (for StormRecorder etc.), e.g. `%{run_queue: n}`."
  def pressure, do: published()[:sample] || %{}

  @doc "Record a shed decision (the consumers call this on every 429/redirect): telemetry + log — false positives must be visible."
  def shed(class, consumer) do
    :telemetry.execute([:bonfire, :overload, :shed], %{count: 1}, %{
      class: class,
      consumer: consumer
    })

    Logger.warning("Overload: shedding #{inspect(class)} traffic (via #{inspect(consumer)})")
    :ok
  end

  @doc "Temporarily force `:ok` for `duration_ms` (the admin 'stand down' button); takes effect immediately."
  def stand_down(server \\ __MODULE__, duration_ms),
    do: GenServer.call(server, {:stand_down, duration_ms})

  defp published, do: :persistent_term.get(@state_key, %{})

  defp stand_down_active?(state) do
    case state[:stand_down_until] do
      until when is_integer(until) -> System.monotonic_time(:millisecond) < until
      _ -> false
    end
  end

  # ── sampler ────────────────────────────────────────────────────────────────

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @impl true
  def init(opts) do
    interval = opts[:interval_ms] || 2_000
    if is_integer(interval), do: {:ok, _} = :timer.send_interval(interval, :tick)

    state = %{
      sample_fun: opts[:sample_fun] || (&default_sample/0),
      config_override: opts[:config],
      level: :ok,
      since: System.monotonic_time(:millisecond),
      up_streaks: %{soft: 0, hard: 0},
      down_streak: 0,
      hard_exited_at: nil,
      stand_down_until: nil,
      sample: %{},
      severity: 0.0
    }

    publish(state, config(state))
    {:ok, state}
  end

  defp default_sample, do: %{run_queue: :erlang.statistics(:total_run_queue_lengths_all)}

  @impl true
  def handle_call({:stand_down, duration_ms}, _from, state) do
    state = %{state | stand_down_until: System.monotonic_time(:millisecond) + duration_ms}
    publish(state, config(state))
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    cfg = config(state)

    if cfg[:mode] == :off do
      {:noreply, state}
    else
      {:noreply, sample_and_step(state, cfg)}
    end
  end

  defp sample_and_step(state, cfg) do
    sample = state.sample_fun.()
    value = sample[:run_queue] || 0
    severity = value / max(cfg[:run_queue_hard], 1)

    :telemetry.execute([:bonfire, :overload, :sample], Map.put(sample, :severity, severity), %{
      level: state.level
    })

    state =
      state
      |> Map.merge(%{sample: sample, severity: severity})
      |> step(value, cfg)
      |> publish(cfg)

    # while elevated, re-assert the UI notice each tick (subscribed LVs re-flash; the flash
    # auto-fading once these stop IS the all-clear — no separate clear machinery). Informational,
    # so based on the computed level even in :monitor mode.
    if state.level != :ok do
      safe(fn ->
        Phoenix.PubSub.local_broadcast(
          Bonfire.Common.PubSub,
          "bonfire:overload",
          {:overload_notice, %{level: state.level, severity: state.severity, node: node()}}
        )
      end)
    end

    state
  end

  # one state-machine step: update streaks, maybe transition one level
  defp step(state, value, cfg) do
    up = %{
      soft: streak(state.up_streaks.soft, value >= cfg[:run_queue_soft]),
      hard: streak(state.up_streaks.hard, value >= cfg[:run_queue_hard])
    }

    # a tick is "clear" for de-escalation when it wouldn't sustain the CURRENT level
    clear? =
      case state.level do
        :hard -> value < cfg[:run_queue_hard]
        :soft -> value < cfg[:run_queue_soft]
        :ok -> true
      end

    down = streak(state.down_streak, clear?)
    state = %{state | up_streaks: up, down_streak: down}

    cond do
      state.level != :hard and up.hard >= cfg[:up_ticks] ->
        transition(state, :hard, value, cfg)

      state.level == :ok and up.soft >= cfg[:up_ticks] ->
        transition(state, :soft, value, cfg)

      state.level == :hard and down >= cfg[:down_ticks] and cooled_down?(state, cfg) ->
        transition(state, :soft, value, cfg)

      state.level == :soft and down >= cfg[:down_ticks] ->
        transition(state, :ok, value, cfg)

      true ->
        state
    end
  end

  defp streak(count, true), do: count + 1
  defp streak(_count, false), do: 0

  defp cooled_down?(state, cfg) do
    # the cooldown starts when :hard was ENTERED (state.since) — relax slowly after an episode
    System.monotonic_time(:millisecond) - state.since >= (cfg[:cooldown_ms] || 0)
  end

  defp transition(state, to, value, cfg) do
    from = state.level

    :telemetry.execute([:bonfire, :overload, :transition], %{severity: state.severity}, %{
      from: from,
      to: to,
      signal: :run_queue,
      value: value
    })

    Logger.warning(
      "Overload level #{from} → #{to} (run_queue=#{value}, severity=#{Float.round(state.severity, 2)}, mode=#{cfg[:mode]})"
    )

    # node-local fan-out to subscribed processes (banner, storm overlay) — overload is per-node
    safe(fn ->
      Phoenix.PubSub.local_broadcast(
        Bonfire.Common.PubSub,
        "bonfire:overload",
        {:overload_transition, %{from: from, to: to, severity: state.severity, node: node()}}
      )
    end)

    # alerting rides the existing SystemMonitor alarm handler (logs + emails the admin)
    safe(fn ->
      cond do
        to == :hard -> :alarm_handler.set_alarm({:overload, "run_queue=#{value}"})
        from == :hard -> :alarm_handler.clear_alarm(:overload)
        true -> :ok
      end
    end)

    %{
      state
      | level: to,
        since: System.monotonic_time(:millisecond),
        down_streak: 0,
        up_streaks: %{soft: 0, hard: 0}
    }
  end

  defp publish(state, cfg) do
    :persistent_term.put(@state_key, %{
      level: state.level,
      severity: state.severity,
      since: state.since,
      sample: state.sample,
      mode: cfg[:mode],
      stand_down_until: state.stand_down_until,
      retry_after: compute_retry_after(state, cfg)
    })

    state
  end

  defp compute_retry_after(state, cfg) do
    minutes_at_level = (System.monotonic_time(:millisecond) - state.since) / 60_000
    base = cfg[:retry_base_s] || 30

    (base * max(state.severity, 1.0) * (1 + minutes_at_level / 5))
    |> round()
    |> min(cfg[:retry_max_s] || 180)
    |> max(base)
  end

  # test-injected absolute config, else the live knobs
  defp config(%{config_override: cfg}) when is_list(cfg), do: cfg
  defp config(_state), do: config()

  @doc "The effective sampler config: knob values with their defaults, THE single source for both the sampler and the tuning card's baseline. Thresholds are multipliers of the machine's scheduler count."
  def config do
    schedulers = System.schedulers_online()
    # read the whole module keyword list in ONE config lookup, then pull knobs from it
    # (the sampler calls this every tick — one cached read keeps it live-tunable without
    # re-reading each knob individually, which also multiplied the debug logging per tick)
    cfg = Bonfire.Common.Config.__get__([__MODULE__], [])
    get = &Keyword.get(cfg, &1, &2)

    soft_multiplier = get.(:run_queue_soft_multiplier, 4)
    hard_multiplier = get.(:run_queue_hard_multiplier, 10)

    [
      run_queue_soft_multiplier: soft_multiplier,
      run_queue_hard_multiplier: hard_multiplier,
      run_queue_soft: soft_multiplier * schedulers,
      run_queue_hard: hard_multiplier * schedulers,
      up_ticks: get.(:up_ticks, 3),
      down_ticks: get.(:down_ticks, 15),
      cooldown_ms: get.(:cooldown_ms, 60_000),
      retry_base_s: get.(:retry_base_s, 30),
      retry_max_s: get.(:retry_max_s, 180),
      mode: get.(:mode, :monitor)
    ]
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end
end
