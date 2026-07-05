defmodule Bonfire.Common.Telemetry do
  @moduledoc """
  Boot-time wiring for logging/telemetry integrations (OTel, Sentry, Ecto/Oban/LiveView handlers), plus the span-end N+1 reporting handlers.

  ## Process-context conventions

  There are exactly TWO sanctioned ways to keep per-request/per-process context in the process dictionary, don't add a third, join a tier:

  - **Tier 1: inherited, set-once request/job CONTEXT** (e.g. `caller_class`, `action`): use `Logger.metadata/1`. It tags every log line AND is readable by telemetry consumers via `ProcessTree.get(:"$logger_metadata$")`, which walks ancestors so spawned Tasks attribute to their origin. Only set-once values belong here: ProcessTree returns the WHOLE metadata map of the NEAREST ancestor that has any, so a process writing its own metadata shadows every inherited key for itself and its descendants — mutable writes here would silently break `caller_class` attribution (degrading it to `:unknown`).

  - **Tier 2: mutable process-local instrumentation state** (timing accumulators like `:server_timing_start`/`:server_timing_custom`, detector state like `EctoSparkles.NPlus1Detector`'s counts): plain namespaced pdict keys via `Process.put/get`, NEVER `Logger.metadata` (per-write map rebuilds, log-line leakage, and the shadowing hazard above). Local reads/writes only.
  """
  require Logger
  alias Bonfire.Common.Extend

  def setup(env, repo_module) do
    setup_opentelemetry(env, repo_module)

    if repo_module do
      EctoSparkles.Log.setup(repo_module)
      # Ecto.DevLogger.install(repo_module)

      # if Code.ensure_loaded?(Mix) and Config.env() == :dev do
      #   OnePlusNDetector.setup(repo_module)
      # end

      IO.puts("Ecto Repo logging is set up...")

      setup_oban()

      IO.puts("Oban logging is set up...")

      setup_server_timing(repo_module)
    end

    setup_liveview_debugging()
    IO.puts("LiveView logging is set up...")

    setup_wobserver()

    # Corsica.Telemetry.attach_default_handler(log_levels: [rejected: :warning, invalid: :warning])
    # IO.puts("Corsica telemetry is set up...")

    if Bonfire.Common.Errors.maybe_sentry_dsn() do
      :logger.add_handler(:bonfire_sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })

      IO.puts("Sentry telemetry is set up...")
    end
  end

  def setup_opentelemetry(_env, repo_module) do
    if System.get_env("ECTO_IPV6") do
      # should we attempt to use ipv6 to connect to telemetry remotes?
      :httpc.set_option(:ipfamily, :inet6fb4)
    end

    if Application.get_env(:opentelemetry, :modularity) != :disabled do
      IO.puts("NOTE: OTLP (open telemetry) data is being collected")

      if Application.get_env(:bonfire, Bonfire.Web.Endpoint, [])[:adapter] in [
           Phoenix.Endpoint.Cowboy2Adapter,
           nil
         ] and Extend.extension_enabled?(:opentelemetry_cowboy) do
        :opentelemetry_cowboy.setup()
      end

      if Extend.module_enabled?(OpentelemetryPhoenix), do: OpentelemetryPhoenix.setup()
      if Extend.module_enabled?(OpentelemetryLiveView), do: OpentelemetryLiveView.setup()

      # Only trace Oban jobs to minimize noise
      if Extend.module_enabled?(OpentelemetryOban), do: OpentelemetryOban.setup(trace: [:jobs])

      if repo_module && Extend.module_enabled?(OpentelemetryEcto),
        do:
          repo_module.config()
          |> Keyword.fetch!(:telemetry_prefix)
          |> OpentelemetryEcto.setup()
    else
      IO.puts("NOTE: OTLP (open telemetry) data will NOT be collected")
    end
  end

  def setup_liveview_debugging do
    :telemetry.attach_many(
      "bonfire-liveview-debug",
      [
        [:phoenix, :live_view, :mount, :exception],
        [:phoenix, :live_view, :handle_params, :exception],
        [:phoenix, :live_view, :handle_event, :exception],
        [:phoenix, :live_view, :handle_info, :exception],
        [:phoenix, :template, :render, :exception]
      ],
      &handle_event/4,
      []
    )

    if Extend.module_exists?(Appsignal.Phoenix.LiveView) &&
         Application.get_env(:appsignal, :config, [])[:active],
       # <--- attach the LiveView Telemetry handlers
       do: Appsignal.Phoenix.LiveView.attach()

    IO.puts("LiveView crash telemetry is set up...")
  end

  def setup_oban do
    :telemetry.attach(
      "bonfire-oban-errors",
      [:oban, :job, :exception],
      &handle_event/4,
      []
    )

    Oban.Telemetry.attach_default_logger(encode: false)
  end

  def setup_server_timing(_repo_module) do
    # NOTE: Server-Timing / page-profiler telemetry handlers are now attached by `Bonfire.UI.Common.PageTimingStorage` when the profiler is ENABLED (boot env or live enable/disable) as attaching them unconditionally made every DB query and router/LV event pay a ProcessTree ancestor walk even with the profiler off.
    IO.puts("Server-Timing telemetry attaches on profiler enable...")
  end

  defp setup_wobserver do
    # if Extend.module_enabled?(Wobserver) do
    # Wobserver.register(:page, {"Task Bunny", :taskbunny, &Status.page/0})
    # Wobserver.register(:metric, [&Status.metrics/0])
    # end
  end

  def handle_event([:oban, :job, :exception], measure, metadata, _) do
    # TODO: check if still necessary now that Sentry SDK has Oban integration
    extra =
      metadata.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Bonfire.Common.Errors.debug_log(extra, metadata.error, metadata.stacktrace, :error)
    :ok
  end

  def handle_event([:phoenix | _rest] = event, _measurements, metadata, _config) do
    Bonfire.Common.Errors.debug_log(
      %{
        event: event,
        liveview_module: metadata.socket.view,
        event: metadata[:event],
        params: metadata[:params],
        uri: metadata[:uri],
        message: metadata[:message]
      },
      metadata.reason,
      metadata.stacktrace,
      metadata.kind
    )

    :ok
  end

  def handle_event(event, _measurements, _metadata, _config) do
    Logger.warn("Telemetry: unhandled event #{inspect(event)}")
    :ok
  end
end
