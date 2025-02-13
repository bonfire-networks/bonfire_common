defmodule Bonfire.Common.Telemetry do
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
    end

    setup_wobserver()

    Corsica.Telemetry.attach_default_handler(log_levels: [rejected: :warning, invalid: :warning])

    IO.puts("Corsica telemetry is set up...")
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

  def setup_oban do
    :telemetry.attach(
      "bonfire-oban-errors",
      [:oban, :job, :exception],
      &Bonfire.Common.Telemetry.handle_event/4,
      []
    )

    Oban.Telemetry.attach_default_logger(encode: false)
  end

  defp setup_wobserver do
    # if Extend.module_enabled?(Wobserver) do
    # Wobserver.register(:page, {"Task Bunny", :taskbunny, &Status.page/0})
    # Wobserver.register(:metric, [&Status.metrics/0])
    # end
  end

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    # TODO: check if still necessary now that Sentry SDK has Oban integration
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Bonfire.Common.Errors.debug_log(extra, meta.error, meta.stacktrace, :error)
  end
end
