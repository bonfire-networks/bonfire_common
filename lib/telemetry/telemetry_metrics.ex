if Code.ensure_loaded?(Telemetry.Metrics) do
  defmodule Bonfire.Common.Telemetry.Metrics do
    use Supervisor
    import Telemetry.Metrics

    def start_link(arg) do
      Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
    end

    @impl true
    def init(_arg) do
      children = [
        # Telemetry poller will execute the given period measurements
        # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
        {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
        # Add reporters as children of your supervision tree.
        # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end

    @millis {:native, :millisecond}

    def metrics do
      [
        # Phoenix
        summary("phoenix.endpoint.stop.duration", unit: @millis),
        summary("phoenix.router_dispatch.stop.duration",
          tags: [:method, :route],
          tag_values: &get_and_put_http_method/1,
          unit: @millis
        ),
        summary("phoenix.error_rendered.duration", unit: @millis),
        summary("phoenix.socket_connected.duration", unit: @millis),
        summary("phoenix.channel_joined.duration", unit: @millis),
        summary("phoenix.channel_joined.duration", unit: @millis),

        # Phoenix LiveView
        summary("phoenix.live_view.mount.stop.duration",
          unit: @millis,
          tags: [:view, :connected?],
          tag_values: &live_view_metric_tag_values/1
        ),
        summary("phoenix.live_view.mount.exception.duration",
          unit: @millis,
          tags: [:view, :connected?],
          tag_values: &live_view_metric_tag_values/1
        ),
        summary("phoenix.live_view.handle_params.stop.duration",
          unit: @millis,
          tags: [:view, :connected?],
          tag_values: &live_view_metric_tag_values/1
        ),
        summary("phoenix.live_view.handle_params.exception.duration",
          unit: @millis,
          tags: [:view, :connected?],
          tag_values: &live_view_metric_tag_values/1
        ),
        summary("phoenix.live_view.handle_event.stop.duration",
          unit: @millis,
          tags: [:view, :event],
          tag_values: fn metadata ->
            Map.put(metadata, :view, "#{inspect(metadata.socket.view)}")
          end
        ),
        summary("phoenix.live_view.handle_event.exception.duration",
          unit: @millis,
          tags: [:view, :event],
          tag_values: fn metadata ->
            Map.put(metadata, :view, "#{inspect(metadata.socket.view)}")
          end
        ),
        summary("phoenix.live_component.handle_event.stop.duration",
          unit: @millis,
          tags: [:view, :event],
          tag_values: fn metadata ->
            Map.put(metadata, :view, "#{inspect(metadata.socket.view)}")
          end
        ),
        summary("phoenix.live_component.handle_event.exception.duration",
          unit: @millis,
          tags: [:view, :event],
          tag_values: fn metadata ->
            Map.put(metadata, :view, "#{inspect(metadata.socket.view)}")
          end
        ),

        # Database Metrics
        summary("bonfire.repo.query.total_time", unit: @millis),
        summary("bonfire.repo.query.decode_time", unit: @millis),
        summary("bonfire.repo.query.query_time", unit: @millis),
        summary("bonfire.repo.query.queue_time", unit: @millis),
        summary("bonfire.repo.query.idle_time", unit: @millis),

        # VM Metrics
        # how busy the schedulers actually were, which no built-in dashboard page shows.
        # `normal` rather than `total`, which is diluted by the always-idle dirty schedulers
        last_value("vm.cpu.normal", unit: :percent),
        summary("vm.memory.total", unit: {:byte, :megabyte}),
        summary("vm.total_run_queue_lengths.total"),
        summary("vm.total_run_queue_lengths.cpu"),
        summary("vm.total_run_queue_lengths.io"),

        # Oban
        summary("oban.workers.memory.total", tags: [:worker])
      ]
    end

    defp periodic_measurements do
      [
        # A module, function and arguments to be invoked periodically.
        # This function must call :telemetry.execute/3 and a metric must be added above.
        # {Bonfire.UI.Common.Web, :count_users, []}
        {Bonfire.Common.Telemetry.Metrics, :oban_worker_memory, []},
        {Bonfire.Common.Telemetry.Metrics, :scheduler_utilization, []}
      ]
    end

    @doc """
    Emits `[:vm, :cpu]` with the percentage of wall time schedulers spent working.

    The BEAM's honest CPU number: unlike `cpu_sup` it is not fooled by container limits, and unlike run queue lengths it says how *busy* the schedulers were rather than how many were waiting.

    `:erlang.statistics(:scheduler_wall_time)` counts cumulatively, so a percentage needs the previous sample. It lives in the calling process's dictionary, which works because `:telemetry_poller` invokes measurements from its own long-lived process, with no extra process and no `:persistent_term` (whose writes would force a global GC scan and would be the wrong trade every 10s). The first call after boot therefore emits nothing.
    """
    def scheduler_utilization do
      sample = scheduler_sample()
      previous = Process.put(:scheduler_wall_time_sample, sample)

      if previous do
        :telemetry.execute([:vm, :cpu], scheduler_percentages(previous, sample), %{})
      end
    end

    @doc """
    Ensures scheduler time is being tracked, and returns a sample to diff against later.

    The flag is global and setting it is not free, so it is set once per calling process rather than on every sample.
    """
    def scheduler_sample do
      if !Process.get(:scheduler_wall_time_enabled) do
        :erlang.system_flag(:scheduler_wall_time, true)
        Process.put(:scheduler_wall_time_enabled, true)
      end

      :erlang.statistics(:scheduler_wall_time) |> Enum.sort()
    end

    @doc """
    The percentage of wall time schedulers spent working between two `scheduler_sample/0` results.

    Shared with `Bonfire.UI.Common.ProcessCpuDashboardPage`, which measures over its own refresh interval rather than the poller's fixed period.
    """
    def scheduler_percentages(previous, current) do
      pairs = Enum.zip(previous, current)

      # ids 1..schedulers_online are the normal ones, dirty-CPU schedulers follow
      {normal, dirty} =
        Enum.split_with(pairs, fn {{id, _, _}, _} -> id <= normal_scheduler_count() end)

      %{
        total: utilisation(pairs),
        normal: utilisation(normal),
        dirty_cpu: utilisation(dirty)
      }
    end

    @doc "How many normal schedulers are online, ie. how many cores the VM will use."
    def normal_scheduler_count, do: :erlang.system_info(:schedulers_online)

    defp utilisation(pairs) do
      {active, total} =
        Enum.reduce(pairs, {0, 0}, fn {{_, active1, total1}, {_, active2, total2}},
                                      {active, total} ->
          {active + (active2 - active1), total + (total2 - total1)}
        end)

      percentage(active, total)
    end

    defp percentage(_active, total) when total <= 0, do: 0.0
    defp percentage(active, total), do: Float.round(active * 100 / total, 1)

    defp get_and_put_http_method(%{conn: %{method: method}} = metadata) do
      Map.put(metadata, :method, method)
    end

    defp live_view_metric_tag_values(metadata) do
      metadata
      |> Map.put(:view, inspect(metadata.socket.view))
      |> Map.put(:connected?, get_connection_status(Phoenix.LiveView.connected?(metadata.socket)))
    end

    defp get_connection_status(true), do: "Connected"
    defp get_connection_status(_), do: "Disconnected"

    def oban_worker_memory() do
      pid = Oban.Registry.whereis(Oban, {:producer, "default"})
      # |> IO.inspect(label: "Oban PID")

      if is_pid(pid) and Process.alive?(pid) do
        %{running: running} = :sys.get_state(pid)

        Enum.map(running, fn {_ref, {pid, executor}} ->
          {executor.job.worker,
           Bonfire.Common.MemoryMonitor.get_memory_usage(executor.job.worker, pid)}
        end)
        # drop nils from workers we failed to check
        |> Enum.reject(&is_nil/1)
        |> Enum.group_by(
          fn {worker, _memory} -> worker end,
          fn {_worker, memory} -> memory end
        )
        |> Enum.map(fn {worker, memory_list} ->
          # sum up the amount of memory used by all instances of the worker.
          # result will be zero if there are no active instances
          :telemetry.execute(
            [:oban, :workers, :memory],
            %{total: Enum.sum(memory_list)},
            %{worker: worker}
          )
        end)
      end
    end
  end
end
