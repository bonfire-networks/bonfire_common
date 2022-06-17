defmodule Bonfire.Common.Config.LoadExtensionsConfig do
  @moduledoc """
  Loads instance Settings from DB into Elixir's Config

  While this module is a GenServer, it is only responsible for querying the settings, putting them in Config, and then exits with :ignore having done so.
  """
  use GenServer, restart: :transient
  use Bonfire.Common.Utils, only: []
  require Logger

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with table data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  # GenServer callback

  @doc false
  def init(_) do
    if Code.ensure_loaded?(:telemetry),
      do: :telemetry.span([:settings, :load_configs], %{}, &load_configs/0),
      else: load_configs()
    :ignore
  end

  def load_configs() do
    extension_configs = Bonfire.Common.ConfigModules.data()
    # |> debug()
    if is_list(extension_configs) and length(extension_configs) >0 do
      Enum.each(extension_configs, & &1.config)
      Logger.info("Extensions' default settings were loaded into runtime config: #{inspect extension_configs}")
    else
      Logger.info("Note: No extensions settings to load into runtime config")
      {:ok, %{skip: "No config loaded"}}
    end
  end

end
