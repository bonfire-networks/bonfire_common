defmodule Bonfire.Common.Telemetry.Storage do
  @moduledoc """
  Keeps a short in-memory history per metric, so LiveDashboard charts open with context.

  `metrics_history/1` is called only when a chart mounts, to backfill points from *before* the page was opened, which is exactly why it cannot be collected on demand, and why it is worth having during an incident and dead weight the rest of the time. So it ships **disabled in prod** and is enabled deliberately, eg. before a load test or while chasing a leak.

  Configure under `config :bonfire_common, #{inspect(__MODULE__)}`:

    * `:enabled` — defaults to true outside prod, false in prod
    * `:history_buffer_size` — points kept per metric, default 50 (~8 min at the 10s poll)
    * `:metrics_filter` — list of metric name prefixes to keep. Defaults to `["vm."]` in prod, so that even when switched on it buffers only poll-driven metrics (~0.1 events/sec) rather than the per-request phoenix/ecto ones (hundreds/sec). Unset elsewhere, keeping every metric as before.
  """

  use GenServer

  alias Bonfire.Common.Config

  @default_buffer_size 50

  @doc """
  History for a metric, or `[]` when collection is off.

  LiveDashboard calls this whenever a chart mounts, including when history is disabled and no
  process is running, so a missing server is an empty chart rather than a crashed page.
  """
  def metrics_history(metric, server \\ __MODULE__) do
    if is_pid(server) or Process.whereis(server) do
      GenServer.call(server, {:data, metric})
    else
      []
    end
  end

  def start_link({metrics, opts}) do
    GenServer.start_link(__MODULE__, {metrics, opts}, name: opts[:name] || __MODULE__)
  end

  def start_link(metrics), do: start_link({metrics, []})

  @doc "Whether history is being collected at all."
  def enabled?(opts \\ []), do: setting(opts, :enabled, Config.env() != :prod)

  @doc "How many points are kept per metric."
  def buffer_size(opts \\ []), do: setting(opts, :history_buffer_size, @default_buffer_size)

  @doc """
  Whether a metric is one we keep history for.

  Matched on name prefix, so `"vm."` covers every VM metric without listing them.
  """
  def keep_metric?(%{name: name}, opts \\ []) do
    case setting(opts, :metrics_filter, default_filter()) do
      nil -> true
      filters -> Enum.any?(filters, &String.starts_with?(Enum.join(name, "."), &1))
    end
  end

  defp default_filter, do: if(Config.env() == :prod, do: ["vm."], else: nil)

  # explicit opts (as passed by tests and by a caller starting a second instance) win over config
  defp setting(opts, key, default) do
    Keyword.get_lazy(opts, key, fn ->
      Application.get_env(:bonfire_common, __MODULE__, [])
      |> Keyword.get(key, default)
    end)
  end

  @impl true
  def init({metrics, opts}) do
    Process.flag(:trap_exit, true)

    metrics = if enabled?(opts), do: Enum.filter(metrics, &keep_metric?(&1, opts)), else: []

    metric_histories_map =
      metrics
      |> Enum.map(fn metric ->
        attach_handler(metric)
        {metric, CircularBuffer.new(buffer_size(opts))}
      end)
      |> Map.new()

    {:ok, metric_histories_map}
  end

  def init(metrics), do: init({metrics, []})

  @impl true
  def terminate(_, metrics) do
    for {metric, _} <- metrics do
      :telemetry.detach({__MODULE__, metric, self()})
    end

    :ok
  end

  defp attach_handler(%{event_name: name_list} = metric) do
    :telemetry.attach(
      {__MODULE__, metric, self()},
      name_list,
      &__MODULE__.handle_event/4,
      {metric, self()}
    )
  end

  def handle_event(_event_name, data, metadata, {metric, server}) do
    if data = Phoenix.LiveDashboard.extract_datapoint_for_metric(metric, data, metadata) do
      GenServer.cast(server, {:telemetry_metric, data, metric})
    end
  end

  @impl true
  def handle_cast({:telemetry_metric, data, metric}, state) do
    case state[metric] do
      nil -> {:noreply, state}
      buffer -> {:noreply, Map.put(state, metric, CircularBuffer.insert(buffer, data))}
    end
  end

  @impl true
  def handle_call({:data, metric}, _from, state) do
    if history = state[metric] do
      {:reply, CircularBuffer.to_list(history), state}
    else
      {:reply, [], state}
    end
  end
end
