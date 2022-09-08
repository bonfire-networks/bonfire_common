# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.NavModules do
  @moduledoc """
  A Global cache of known nav modules to be queried by associated schema, or vice versa.

  Use of the NavModules Service requires:

  1. Exporting `declared_nav/0` in relevant modules (or use the `declare_nav_component/2` or `declare_nav_link/2` macros), returning a Module or otp_app atom
  2. To populate `:bonfire, :ui_modules_search_path` in nav the list of OTP applications where nav_modules are declared.
  3. Start the `Bonfire.Common.NavModules` application before querying.
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
  A query is either a nav_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with nav_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data() do
    :persistent_term.get(__MODULE__)
  rescue e in ArgumentError ->
    debug("Gathering a list of nav modules...")
    populate()
  end

  @doc "Get a nav identified by schema"
  def nav(module) when is_atom(module) do
    Utils.maybe_apply(module, :declared_nav, [], &nav_function_error/2)
  end

  def nav() do
    Enum.map(data(), &nav/1)
  end

  @spec nav_modules() :: [atom]
  @doc "Look up many navs at once, throw :not_found if any of them are not found"
  def nav_modules() do
    data()
  end

  def nav_function_error(error, _args) do
    warn(error, "NavModules - there's no nav module declared for this schema: 1) No function declared_nav/0 that returns this schema atom. 2)")

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
      |> Enum.filter(&declares_nav_module?/1)
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
  defp declares_nav_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :declared_nav, 0)

  # called by populate/0
  defp index(mod, acc), do: acc ++ [mod] # only put the module name in ETS
  # defp index(mod, acc), do: index(acc, mod, mod.declared_nav()) # put data in ETS

  # called by index/2
  # defp index(acc, declaring_module, true) do
  #   acc ++ [declaring_module]
  # end

  # defp index(acc, declaring_module, _) do
  #   warn(declaring_module, "Skip")
  # end

end
