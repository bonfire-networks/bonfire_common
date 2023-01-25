# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.SettingsModule do
  @moduledoc """
  Settings nav & components
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []
  import Bonfire.Common.Enums, only: [filter_empty: 2]

  @doc "Declares a component component"
  @callback declared_component() :: any

  @doc "Declares a nav module, with links or nav components"
  @callback declared_nav() :: any

  @doc "Get navs for an extension"
  def nav(app) when is_atom(app) and not is_nil(app) do
    app_modules()[app]
    # |> debug
    |> modules_nav()
  end

  def modules_nav(modules) when is_list(modules) do
    modules
    # |> debug
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
    |> modules_nav()
    # |> debug()
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

  @doc "Get components identified by their module"
  def modules_component(modules) when is_list(modules) do
    modules
    |> Enum.map(fn
      {module, props} ->
        Utils.maybe_apply(module, :declared_component, [], &component_function_error/2)
        |> Enum.into(%{props: props})

      module ->
        Utils.maybe_apply(module, :declared_component, [], &component_function_error/2)
    end)
  end

  def modules_component(_), do: []

  @doc "Load components for an extension"
  def components(extension) do
    app_modules()[extension]
    |> modules_component()
    |> filter_empty([])
  end

  @doc "Load all components at once"
  def components() do
    modules()
    |> modules_component()
    |> filter_empty([])
  end

  @doc "List extensions that have settings component(s)"
  def extension_has_components?(extension, modules \\ nil) do
    case (modules || app_modules()[extension])
         |> modules_with_component() do
      [] -> false
      _ -> true
    end
  end

  defp modules_with_component(modules) when is_list(modules) do
    modules
    # |> debug
    |> Enum.filter(fn
      {module, _props} ->
        module_enabled?(module) and function_exported?(module, :declared_component, 0)

      module ->
        module_enabled?(module) and function_exported?(module, :declared_component, 0)
    end)
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
