# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ContextModules do
  @moduledoc """
  A Global cache of known context modules to be queried by associated schema, or vice versa.

  Use of the ContextModules Service requires:

  1. Exporting `context_module/0` in relevant modules (in schemas pointing to context modules and/or in context modules pointing to schemas), returning a Module atom
  2. To populate `:pointers, :search_path` in config the list of OTP applications where context_modules are declared.
  3. Start the `Bonfire.Common.ContextModules` application before querying.
  4. OTP 21.2 or greater, though we recommend using the most recent
     release available.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """

  require Logger
  alias Bonfire.Common.Utils

  @doc """
  Given an object or schema module name, run a function on the associated context module.
  """
  def maybe_apply(
        object_schema_or_context,
        fun,
        args \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_apply(schema_or_context, fun, args, fallback_fun)
      when is_atom(schema_or_context) and is_atom(fun) and is_list(args) and
             is_function(fallback_fun) do

    if Utils.module_enabled?(schema_or_context) do

      object_context_module = maybe_context_module(schema_or_context)

      Utils.maybe_apply(
        object_context_module,
        fun,
        args,
        fallback_fun
      )

    else
      fallback_fun.(
        "ContextModules: Module could be found: #{schema_or_context}",
        args
      )
    end
  end

  def maybe_apply(
        %{__struct__: schema} = _object,
        fun,
        args,
        fallback_fun
      ) do
    maybe_apply(schema, fun, args, fallback_fun)
  end

  def maybe_apply(object_schema_or_context, fun, args, fallback_fun)
      when not is_list(args) do
    maybe_apply(object_schema_or_context, fun, [args], fallback_fun)
  end

  def apply_error(error, args, level \\ :error) do
    Logger.log(level, "Bonfire.Common.ContextModules: Error running function: #{error} with args: (#{inspect args})")

    {:error, error}
  end


  use GenServer, restart: :transient

  @typedoc """
  A query is either a context_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with context_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data(), do: :persistent_term.get(__MODULE__) #, data_init())

  defp data_init() do
    Logger.error "The ContextModules service was not started. Please add it to your Application."
    populate()
  end

  @spec context_module(query :: query) :: {:ok, atom} | {:error, :not_found}
  @doc "Get a context identified by schema"
  def context_module(query) when is_binary(query) or is_atom(query) do
    case Map.get(data(), query) do
      nil -> {:error, :not_found}
      other -> {:ok, other}
    end
  end

  @doc "Look up a context, throw :not_found if not found."
  def context_module!(query), do: Map.get(data(), query) || throw(:not_found)

  @spec context_modules([binary | atom]) :: [binary]
  @doc "Look up many contexts at once, throw :not_found if any of them are not found"
  def context_modules(modules) do
    data = data()
    Enum.map(modules, &Map.get(data, &1))
  end

  def maybe_context_module(query) do
    with {:ok, module} <- context_module(query) do
      module
    else _ ->
      Utils.maybe_apply(query, :context_module, [], &context_function_error/2)
    end
  end

  def context_function_error(error, _args, level \\ :info) do
    Logger.log(level, "ContextModules - there's no context module declared for this schema: 1) No function context_module/0 that returns this schema atom. 2) #{error}")

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
      search_path()
      # |> IO.inspect
      |> Enum.flat_map(&app_modules/1)
      # |> IO.inspect(limit: :infinity)
      |> Enum.filter(&declares_context_module?/1)
      # |> IO.inspect(limit: :infinity)
      |> Enum.reduce(%{}, &index/2)
      # |> IO.inspect
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods

  # called by populate/0
  defp search_path(), do: Application.fetch_env!(:bonfire, :context_modules_search_path)

  # called by populate/0
  defp declares_context_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :context_module, 0)

  # called by populate/0
  defp index(mod, acc), do: index(acc, mod, mod.context_module())

  # called by index/2
  defp index(acc, declaring_module, context_module) do
    Map.merge(acc, %{declaring_module => context_module, context_module => declaring_module})
  end


end
