# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ExtensionModules do
  @moduledoc """
  A Global cache of known extension modules to be queried by associated schema, or vice versa.

  Use of the ExtensionModules Service requires:

  1. Exporting `declared_extension/0` in relevant modules (or use the `declare_extension/2` macro), returning a map
  2. To populate `:bonfire, :ui_modules_search_path` in extension the list of OTP applications where extension_modules are declared.
  3. Start the `Bonfire.Common.ExtensionModules` application before querying.
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
  A query is either a extension_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with extension_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data() do
    :persistent_term.get(__MODULE__)
  rescue
    e in ArgumentError ->
      debug("Gathering a list of extension modules...")
      populate()
  end

  @doc "Get a extension identified by schema"
  def extension(app) when is_atom(app) and not is_nil(app) do
    data()[app]
    # |> debug
    |> extension_module()
  end

  def extension({app, module}), do: extension_module({app, module})
  def extension(_), do: nil

  def extension_module({app, module}), do: {app, extension_module(module)}

  def extension_module(module) when is_atom(module) do
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

  def default_nav(app) do
    extension(app)[:default_nav]
    |> Bonfire.Common.NavModules.nav()
  end

  def extensions() do
    Enum.map(data(), &extension_module/1)
  end

  def extension_function_error(error, _args) do
    warn(
      error,
      "NavModules - there's no extension module declared for this schema: 1) No function declared_extension/0 that returns this schema atom. 2)"
    )

    nil
  end

  # GenServer callback

  @doc false
  def init(_) do
    populate()
    :ignore
  end

  def populate() do
    # |> IO.inspect(limit: :infinity)
    indexed = Utils.filter_empty(search_app_modules(), [])

    # |> IO.inspect(limit: :infinity)
    # |> Enum.reduce([], &index/2)
    # |> debug()
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  def search_app_modules(search_path \\ search_path()) do
    Enum.map(search_path, &app_modules/1)
  end

  defp search_path(),
    do: Application.fetch_env!(:bonfire, :ui_modules_search_path)

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))

  defp app_modules(app, mods) when is_list(mods) do
    case Enum.filter(mods, &declares_extension_module?/1) do
      [mod] -> {app, mod}
      [] -> nil
    end
  end

  defp app_modules(_, _), do: nil

  defp declares_extension_module?(module),
    do:
      Code.ensure_loaded?(module) and
        function_exported?(module, :declared_extension, 0)

  # called by populate/0
  # defp index(mod, acc), do: acc ++ [mod] # only put the module name in ETS
  # defp index(mod, acc), do: index(acc, mod, mod.declared_extension()) # put data in ETS

  # called by index/2
  # defp index(acc, declaring_module, true) do
  #   acc ++ [declaring_module]
  # end

  # defp index(acc, declaring_module, _) do
  #   warn(declaring_module, "Skip")
  # end
end
