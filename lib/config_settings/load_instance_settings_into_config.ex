defmodule Bonfire.Common.Settings.LoadInstanceConfig do
  @moduledoc """
  Loads instance Settings (see `Bonfire.Common.Settings`) from DB into OTP config / application env (see `Bonfire.Common.Config`)

  While this module is a GenServer, it is only responsible for querying the settings, putting them in Config, and then exits with :ignore having done so.
  """
  use GenServer, restart: :transient
  require Logger
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Config
  alias Bonfire.Common.Settings

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with table data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  # GenServer callback

  @doc false
  def init(_) do
    if Code.ensure_loaded?(:telemetry),
      do: :telemetry.span([:settings, :load_config], %{}, &load_config/0),
      else: load_config()

    :ignore
  end

  def load_config() do
    settings =
      Settings.load_instance_settings()
      |> Enums.maybe_to_keyword_list(true, false)

    if settings do
      Logger.info("Loading instance Settings from DB into the app's Config")

      put = Config.put_tree(settings, already_prepared: true)

      # generate an updated reverse router based on extensions that are enabled/disabled
      Extend.generate_reverse_router!()

      # boot re-assert for instance performance tuning: snapshot the boot baseline (pg_settings
      # etc.) and re-apply the admin's saved intent on top — the durable copy is the Settings
      # just loaded; the projections (ALTER SYSTEM, Logger level, app env) must be rebuilt each
      # boot (on recipe deploys the DB entrypoint even regenerates postgresql.auto.conf).
      # No-op when nothing deviates from the baseline; must never block/fail the boot.
      reassert_instance_tuning()

      {put, Map.new(settings)}
    else
      Logger.info("No instance Settings to load into Config")
      {:ok, %{skip: "No settings to load"}}
    end
  end

  defp reassert_instance_tuning do
    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Common.Settings.Calm.InstanceTuning,
      :apply_current,
      [],
      fallback_return: nil
    )
  rescue
    e -> Logger.warning("Could not re-assert instance tuning at boot: #{inspect(e)}")
  end
end
