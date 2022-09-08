# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.WidgetModules do
  @moduledoc """
  A Global cache of known widget modules to be queried by associated schema, or vice versa.

  Use of the WidgetModules Service requires:

  1. Exporting `declared_widget/0` in relevant modules (or use the `declare_widget/2` macro), returning a map
  2. To populate `:bonfire, :ui_modules_search_path` in widget the list of OTP applications where widget_modules are declared.
  3. Start the `Bonfire.Common.WidgetModules` application before querying.
  4. OTP 21.2 or greater, though we recommend using the most recent
     release available.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """

  use Bonfire.Common.Utils, only: []

  use GenServer, restart: :transient

  @typedoc """
  A query is either a widget_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with widget_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data() do
    :persistent_term.get(__MODULE__)
  rescue e in ArgumentError ->
    debug("Gathering a list of widget modules...")
    populate()
  end

  @doc "Get a widget identified by schema"
  def widget(module) when is_atom(module) do
    Utils.maybe_apply(module, :declared_widget, [], &widget_function_error/2)
  end

  def widgets() do
    Enum.map(data(), &widget/1)
  end

  @spec widget_modules() :: [atom]
  @doc "Look up many widgets at once, throw :not_found if any of them are not found"
  def widget_modules() do
    data()
  end

  def widget_function_error(error, _args) do
    warn(error, "WidgetModules - there's no widget module declared for this schema: 1) No function declared_widget/0 that returns this schema atom. 2)")

    nil
  end

  # GenServer callback

  @doc false
  def init(_) do
    populate()
    :ignore
  end

  def populate() do
    indexed =
      search_app_modules()
      # |> IO.inspect(limit: :infinity)
      |> Enum.filter(&declares_widget_module?/1)
      # |> IO.inspect(limit: :infinity)
      |> Enum.reduce([], &index/2)
      # |> debug()
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  def search_app_modules(search_path \\ search_path()) do
    search_path
    |> Enum.flat_map(&app_modules/1)
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods

  # called by populate/0
  defp search_path(), do: Application.fetch_env!(:bonfire, :ui_modules_search_path)

  # called by populate/0
  defp declares_widget_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :declared_widget, 0)

  # called by populate/0
  defp index(mod, acc), do: acc ++ [mod] # only put the module name in ETS
  # defp index(mod, acc), do: index(acc, mod, mod.declared_widget()) # put data in ETS

  # called by index/2
  # defp index(acc, declaring_module, true) do
  #   acc ++ [declaring_module]
  # end

  # defp index(acc, declaring_module, _) do
  #   warn(declaring_module, "Skip")
  # end

end
