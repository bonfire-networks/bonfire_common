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

  use Bonfire.Common.Utils, only: [e: 3]

  def maybe_query(
        schema,
        filters \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_query(schema, args, fallback_fun)
      when is_atom(schema)
      and ( is_list(args) or is_map(args) or is_atom(args) or is_tuple(args) )
      and is_function(fallback_fun) do

    case maybe_query_module(schema) do
      query_module when is_atom(query_module) and not is_nil(query_module) ->

        debug(args, "maybe_query args")
        paginate = if is_list(args), do: e(Enum.at(args, 0), :paginate, nil) || e(Enum.at(args, 1), :paginate, nil)

        if not is_nil(paginate) and paginate != %{} and function_exported?(query_module, :query_paginated, length(args)) do

            Utils.maybe_apply(
              query_module,
              :query_paginated,
              args,
              fallback_fun
            )

        else
          Utils.maybe_apply(
              query_module,
              :query,
              args,
              fallback_fun
            )
        end


      not_found ->
        query_function_error("No queries_modules/0 on #{schema} that returns this context module 3) A malfunction of the QueriesModule service (got: #{inspect not_found})", args, :info)
    end

  end

  def maybe_query(
        %{__struct__: schema} = _object,
        args,
        fallback_fun
      ) do
    maybe_query(schema, args, fallback_fun)
  end

  def maybe_query(object_schema, args, fallback_fun)
      when not is_list(args) do
    maybe_query(object_schema, [args], fallback_fun)
  end

  def apply_error(error, args) do
    warn("QueryModules - could not query: #{error} - Query args: #{inspect args}")

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

  def data(), do: :persistent_term.get(__MODULE__)

  @spec query_module(query :: query) :: {:ok, atom} | {:error, :not_found}
  @doc "Get a Queryable identified by name or id."
  def query_module(query) when is_binary(query) or is_atom(query) do
    case Map.get(data(), query) do
      nil -> {:error, :not_found}
      other -> {:ok, other}
    end
  end

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
      # IO.inspect(maybe_query_module: module)
      module
    else _ ->
      Utils.maybe_apply(query, :queries_module, [], &query_function_error/2)
    end
  end

  def query_function_error(error, _args, level \\ :info) do
    warn(error, "QueryModules - there's no known query module for this schema, because one of: 1) No function queries_module/0 on a context module, that returns this schema's atom. 2)")

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
      # |> IO.inspect(label: "Query modules")
    :persistent_term.put(__MODULE__, indexed)
    indexed
  end

  defp app_modules(app), do: app_modules(app, Application.spec(app, :modules))
  defp app_modules(_, nil), do: []
  defp app_modules(_, mods), do: mods

  # called by populate/0
  defp search_path(), do: Application.fetch_env!(:bonfire, :query_modules_search_path)

  # called by populate/0
  defp declares_queries_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :queries_module, 0)

  # called by populate/0
  defp index(mod, acc), do: index(acc, mod, mod.queries_module())

  # called by index/2
  defp index(acc, declaring_module, query_module) do
    Map.merge(acc, %{
      declaring_module => query_module,
      query_module => declaring_module
      })
  end


end
