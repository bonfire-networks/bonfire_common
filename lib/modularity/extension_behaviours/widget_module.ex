# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.WidgetModule do
  @moduledoc """
  Widgets: components that can be added to the dashboard or sidebards
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
