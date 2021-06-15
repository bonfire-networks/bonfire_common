defmodule Bonfire.Common.QueryModules do
  @moduledoc """
  Properly query some data using the appropriate module depending on its schema.

  Back by a global cache of known query_modules to be queried by their schema, or vice versa.

  Use of the QueryModules Service requires:

  1. Exporting `queries_module/0` in relevant modules (in schemas pointing to query modules and/or in query modules pointing to schemas), returning a Module atom
  2. To populate `:pointers, :search_path` in config the list of OTP applications where query_modules are declared.
  3. Start the `Bonfire.Common.QueryModules` application before querying.
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

  def maybe_query(
        schema_or_query_module,
        filters \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_query(schema_or_query_module, args, fallback_fun)
      when is_atom(schema_or_query_module)
      and ( is_list(args) or is_map(args) or is_atom(args) or is_tuple(args) )
      and is_function(fallback_fun) do

    if Utils.module_enabled?(schema_or_query_module) do

      query_module = maybe_query_module(schema_or_query_module) || schema_or_query_module

      # IO.inspect(try_query: query_module)
      # IO.inspect(args, label: "filters")

      Utils.maybe_apply(
        query_module,
        :query,
        args,
        fallback_fun
      )

    else
      fallback_fun.(
        "QueryModules: Module could not be found: #{schema_or_query_module}",
        args
      )
    end
  end

  def maybe_query(
        %{__struct__: schema} = _object,
        args,
        fallback_fun
      ) do
    maybe_query(schema, args, fallback_fun)
  end

  def maybe_query(object_schema_or_query_module, args, fallback_fun)
      when not is_list(args) do
    maybe_query(object_schema_or_query_module, [args], fallback_fun)
  end

  def apply_error(error, args, level \\ :error) do
    Logger.log(level, "QueryModules - could not query: #{error} - with args: (#{inspect args})")

    nil
  end

  use GenServer, restart: :transient

  @typedoc """
  A query is either a query_module name atom or (Pointer) id binary
  """
  @type query :: binary | atom

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with query_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def data(), do: :persistent_term.get(__MODULE__) #, data_init())

  defp data_init() do
    Logger.error "The QueryModules was not started. Please add it to your Application."
    populate()
  end

  @spec query_module(query :: query) :: {:ok, atom} | {:error, :not_found}
  @doc "Get a Queryable identified by name or id."
  def query_module(query) when is_binary(query) or is_atom(query) do
    case Map.get(data(), query) do
      nil -> {:error, :not_found}
      other -> {:ok, other}
    end
  end

  @spec query_module!(query) :: Queryable.t
  @doc "Look up a Queryable by name or id, throw :not_found if not found."
  def query_module!(query), do: Map.get(data(), query) || throw(:not_found)

  @spec query_modules([binary | atom]) :: [binary]
  @doc "Look up many ids at once, throw :not_found if any of them are not found"
  def query_modules(modules) do
    data = data()
    Enum.map(modules, &Map.get(data, &1))
  end

  def maybe_query_module(query) do
    with {:ok, module} <- query_module(query) do
      module
    else _ ->
      Utils.maybe_apply(query, :queries_module, [], &query_function_error/2)
    end
  end

  def query_function_error(error, _args, level \\ :info) do
    Logger.log(level, "QueryModules - there's no query module declared for this schema: 1) No function queries_module/0 that returns this schema atom. 2) #{error}")

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
      |> Enum.flat_map(&app_modules/1)
      |> Enum.filter(&declares_queries_module?/1)
      # |> IO.inspect
      |> Enum.reduce(%{}, &index/2)
      # |> IO.inspect
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods

  # called by populate/0
  defp search_path(), do: Application.fetch_env!(:bonfire, :query_modules_search_path)

  # called by populate/0
  defp declares_queries_module?(module), do: function_exported?(module, :queries_module, 0)

  # called by populate/0
  defp index(mod, acc), do: index(acc, mod, mod.queries_module())

  # called by index/2
  defp index(acc, declaring_module, query_module) do
    Map.merge(acc, %{declaring_module => query_module, query_module => declaring_module})
  end




end
