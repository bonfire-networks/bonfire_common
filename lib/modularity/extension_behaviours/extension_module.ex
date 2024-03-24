# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ExtensionModule do
  @moduledoc """
  A global cache of known Bonfire extensions and their metadata.
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
  def extension(app) when is_binary(app), do: Types.maybe_to_atom!(app) |> extension()
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

  def default_nav(%{default_nav: default_nav}) do
    default_nav
    |> Bonfire.UI.Common.NavModule.nav()
  end

  def default_nav(app) when is_atom(app) do
    # Bonfire.UI.Common.NavModule.nav(app) || 
    extension(app)[:default_nav]
    |> Bonfire.UI.Common.NavModule.nav() ||
      []
  end

  def default_nav(apps) when is_list(apps) do
    Enum.flat_map(apps, &default_nav/1)
  end

  def default_nav(_) do
    []
  end

  def default_nav() do
    default_nav_apps()
    |> default_nav()
  end

  def default_nav_apps() do
    Config.get([:ui, :default_nav_extensions], [:bonfire_ui_common, :bonfire_ui_social])
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
