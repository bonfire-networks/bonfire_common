# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.NavModule do
  @moduledoc """
  Add items to extensions' navigation sidebar.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []
  import Bonfire.Common.Enums, only: [filter_empty: 2]

  @doc "Declares a nav module, with links or nav components"
  @callback declared_nav() :: any

  @doc "Get navs for an extension"
  def nav(app) when is_atom(app) and not is_nil(app) do
    app_modules()[app]
    # |> debug
    |> nav()
  end

  def nav({app, modules}), do: {app, nav(modules)}

  def nav(modules) when is_list(modules) do
    Enum.map(modules, fn
      {module, props} ->
        Utils.maybe_apply(module, :declared_nav, [], &nav_function_error/2)
        |> Enum.into(%{props: props})

      module ->
        Utils.maybe_apply(module, :declared_nav, [], &nav_function_error/2)
    end)
  end

  def nav(_), do: nil

  @doc "Load all navs"
  def nav() do
    Enum.map(modules(), &nav/1)
    |> filter_empty([])
  end

  def nav_function_error(error, _args) do
    warn(
      error,
      "NavModule - there's no nav module declared for this schema: 1) No function declared_nav/0 that returns this schema atom. 2)"
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
