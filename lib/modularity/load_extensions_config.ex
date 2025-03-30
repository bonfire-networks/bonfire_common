defmodule Bonfire.Common.Config.LoadExtensionsConfig do
  @moduledoc """
  Loads instance Settings from DB into Elixir's Config

  While this module is a GenServer, it is only responsible for querying the settings, putting them in Config, and then exits with :ignore having done so.
  """
  use GenServer, restart: :transient
  use Bonfire.Common.Utils, only: [maybe_apply: 2]
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

  def load_configs(extras \\ []) do
    modules =
      (Bonfire.Common.ConfigModule.modules() ++ List.wrap(extras))
      |> Enum.uniq()

    # |> debug()

    if is_list(modules) and modules != [] do
      Enum.each(modules, &apply(&1, :config, []))

      Logger.info(
        "Extensions' default settings were loaded from their ConfigModule into runtime config: #{inspect(modules)}"
      )
    else
      Logger.info("Note: No extensions ConfigModule were found to load into runtime config")
      IO.inspect(modules)
      {:ok, %{skip: "No config loaded"}}
    end
  end
end
