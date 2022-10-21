# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.NavModule do
  @moduledoc """
  A Global cache of known nav modules to be queried by associated schema, or vice versa.

  Use of the NavModule Service requires:

  1. Exporting `declared_nav/0` in relevant modules (or use the `declare_nav_component/2` or `declare_nav_link/2` macros), returning a Module or otp_app atom
  2. To populate `:bonfire, :ui_modules_search_path` in nav the list of OTP applications where nav_modules are declared.
  3. Start the `Bonfire.Common.NavModule` application before querying.
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
  def navs() do
    Enum.map(modules(), &nav/1)
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
