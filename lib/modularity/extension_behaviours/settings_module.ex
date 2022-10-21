# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.SettingsModule do
  @moduledoc """
  Settings nav & components
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: [filter_empty: 2]

  @doc "Declares a component component"
  @callback declared_component() :: any

  @doc "Declares a nav module, with links or nav components"
  @callback declared_nav() :: any

  @doc "Get navs for an extension"
  def nav(app) when is_atom(app) and not is_nil(app) do
    app_modules()[app]
    # |> debug
    |> nav()
  end

  def nav(modules) when is_list(modules) do
    modules
    |> debug
    |> Enum.map(fn
      {module, props} ->
        Utils.maybe_apply(module, :declared_settings_nav, [], &nav_function_error/2)
        |> Enum.into(%{props: props})

      module ->
        Utils.maybe_apply(module, :declared_settings_nav, [], &nav_function_error/2)
    end)
  end

  @doc "Load all navs"
  def nav() do
    modules()
    |> nav()
    |> debug()
    |> filter_empty([])
  end

  # def nav() do
  #   Enum.map(app_modules(), &nav/1)
  #   |> filter_empty([])
  # end

  def nav_function_error(error, _args) do
    warn(
      error,
      "NavModule - there's no nav module declared for this schema: 1) No function declared_nav/0 that returns this schema atom. 2)"
    )

    nil
  end

  @doc "Get a component identified by its module"
  def component(module) when is_atom(module) do
    Utils.maybe_apply(module, :declared_component, [], &component_function_error/2)
  end

  @doc "Load components for an extension"
  def components(extension) do
    Enum.map(app_modules()[extension], &component/1)
    |> filter_empty([])
  end

  @doc "Load all components at once"
  def components() do
    Enum.map(modules(), &component/1)
    |> filter_empty([])
  end

  def component_function_error(error, _args) do
    warn(
      error,
      "SettingsModule - there's no component module declared for this schema: 1) No function declared_component/0 that returns this schema atom. 2)"
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
