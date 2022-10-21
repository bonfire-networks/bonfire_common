# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.WidgetModule do
  @moduledoc """
  A Global cache of known widget modules to be queried by associated schema, or vice versa.

  Use of the WidgetModule Service requires:

  1. Exporting `declared_widget/0` in relevant modules (or use the `declare_widget/2` macro), returning a map
  2. To populate `:bonfire, :ui_modules_search_path` in widget the list of OTP applications where widget_modules are declared.
  3. Start the `Bonfire.Common.WidgetModule` application before querying.
  4. OTP 21.2 or greater, though we recommend using the most recent
     release available.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a widget component"
  @callback declared_widget() :: any

  @doc "Get a widget identified by module"
  def widget(module) when is_atom(module) do
    Utils.maybe_apply(module, :declared_widget, [], &widget_function_error/2)
  end

  @doc "Load widgets for an extension"
  def widgets(extension) do
    Enum.map(app_modules()[extension], &widget/1)
  end

  @doc "Load all widgets at once"
  def widgets() do
    Enum.map(modules(), &widget/1)
  end

  def widget_function_error(error, _args) do
    warn(
      error,
      "WidgetModule - there's no widget module declared for this schema: 1) No function declared_widget/0 that returns this schema atom. 2)"
    )

    nil
  end

  def app_modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_app_modules(__MODULE__)
  end

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end
end
