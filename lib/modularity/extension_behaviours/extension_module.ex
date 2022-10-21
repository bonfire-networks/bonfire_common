# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ExtensionModule do
  @moduledoc """
  A Global cache of known extension modules to be queried by associated schema, or vice versa.

  Use of the ExtensionModule Service requires:

  1. Exporting `declared_extension/0` in relevant modules (or use the `declare_extension/2` macro), returning a map
  2. To populate `:bonfire, :ui_modules_search_path` in extension the list of OTP applications where declared_extensions are declared.
  3. Start the `Bonfire.Common.ExtensionModule` application before querying.
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

  @doc "Declares a Bonfire extensions"
  @callback declared_extension() :: any

  @doc "Get a extension identified by schema"
  def extension(app) when is_atom(app) and not is_nil(app) do
    app_modules()[app]
    # |> debug
    |> declared_extension()
  end

  def extension({app, module}), do: declared_extension({app, module})
  def extension(_), do: nil

  def declared_extension({app, module}), do: {app, declared_extension(module)}

  def declared_extension([module]), do: declared_extension(module)

  def declared_extension(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :declared_extension, 0),
      do:
        apply(
          module,
          :declared_extension,
          []
        )

    # Utils.maybe_apply(
    #   module,
    #   :declared_extension,
    #   [],
    #   &extension_function_error/2
    # )
  end

  def declared_extensions(modules \\ app_modules())

  def declared_extensions(modules) when is_list(modules) or is_map(modules) do
    Enum.map(modules, &declared_extension/1)
  end

  def default_nav(app) do
    extension(app)[:default_nav]
    |> Bonfire.Common.NavModule.nav()
  end

  def extension_function_error(error, _args) do
    warn(
      error,
      "NavModule - there's no extension module declared for this schema: 1) No function declared_extension/0 that returns this schema atom. 2)"
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
