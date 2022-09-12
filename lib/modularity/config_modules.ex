# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ConfigModules do
  @moduledoc """
  A Global cache of known config modules to be queried by associated schema, or vice versa.

  Use of the ConfigModules Service requires:

  1. Exporting `config_module/0` in relevant modules, returning a Module or otp_app atom
  2. To populate `:bonfire, :config_modules_search_path` in config the list of OTP applications where config_modules are declared.
  3. Start the `Bonfire.Common.ConfigModules` application before querying.
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
  A query is either a config_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with config_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data() do
    :persistent_term.get(__MODULE__)
  rescue
    e in ArgumentError ->
      debug("Gathering a list of config modules...")
      populate()
  end

  @spec config_module(query :: query) :: {:ok, atom} | {:error, :not_found}
  @doc "Get a config identified by schema"
  def config_module(query) when is_binary(query) or is_atom(query) do
    case Map.get(data(), query) do
      nil -> {:error, :not_found}
      other -> {:ok, other}
    end
  end

  @doc "Look up a config, throw :not_found if not found."
  def config_module!(query), do: Map.get(data(), query) || throw(:not_found)

  @spec config_modules([binary | atom]) :: [binary]
  @doc "Look up many configs at once, throw :not_found if any of them are not found"
  def config_modules(modules) do
    data = data()
    Enum.map(modules, &Map.get(data, &1))
  end

  def maybe_config_module(query) do
    with {:ok, module} <- config_module(query) do
      module
    else
      _ ->
        Utils.maybe_apply(query, :config_module, [], &config_function_error/2)
    end
  end

  def config_function_error(error, _args) do
    warn(
      error,
      "ConfigModules - there's no config module declared for this schema: 1) No function config_module/0 that returns this schema atom. 2)"
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
    indexed =
      search_app_modules()
      # |> IO.inspect(limit: :infinity)
      |> Enum.filter(&declares_config_module?/1)
      # |> IO.inspect(limit: :infinity)
      |> Enum.reduce([], &index/2)

    # |> debug()
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  def search_app_modules(search_path \\ search_path()) do
    Enum.flat_map(search_path, &app_modules/1)
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods

  # called by populate/0
  defp search_path(),
    do: Application.fetch_env!(:bonfire, :config_modules_search_path)

  # called by populate/0
  defp declares_config_module?(module),
    do:
      Code.ensure_loaded?(module) and
        function_exported?(module, :config_module, 0)

  # called by populate/0
  defp index(mod, acc), do: index(acc, mod, mod.config_module())

  # called by index/2
  defp index(acc, declaring_module, true) do
    acc ++ [declaring_module]
  end

  defp index(acc, declaring_module, _) do
    warn(declaring_module, "Skip")
  end
end
