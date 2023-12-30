defmodule Bonfire.Common.QueryModule do
  @moduledoc """
  Properly query some data using the appropriate module depending on its schema.

  Back by a global cache of known query_modules to be queried by their schema, or vice versa.

  Use of the QueryModule Service requires:

  1. Exporting `query_module/0` in relevant modules (in schemas pointing to query modules and/or in query modules pointing to schemas), returning a Module atom
  2. To populate `:nee, :search_path` in config the list of OTP applications where query_modules are declared.
  3. Start the `Bonfire.Common.QueryModule` application before querying.
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
  use Bonfire.Common.Utils, only: [e: 3]

  @doc "Declares a query module"
  @callback query_module() :: any

  @doc "Points to the related schema module"
  @callback schema_module() :: atom

  @doc "Points to the related context module"
  @callback context_module() :: atom

  def maybe_query(
        schema,
        filters \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_query(schema, args, fallback_fun)
      when is_atom(schema) and
             (is_list(args) or is_map(args) or is_atom(args) or is_tuple(args)) and
             is_function(fallback_fun) do
    case maybe_query_module(schema) do
      query_module when is_atom(query_module) and not is_nil(query_module) ->
        debug(args, "maybe_query args")

        paginate =
          if is_list(args),
            do:
              e(Enum.at(args, 0), :paginate, nil) ||
                e(Enum.at(args, 1), :paginate, nil)

        if not is_nil(paginate) and paginate != %{} and
             function_exported?(query_module, :query_paginated, length(args)) do
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
        query_function_error(
          "No query_module/0 on #{schema} that returns this context module 3) A malfunction of the QueriesModule service (got: #{inspect(not_found)})",
          args,
          :info
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

  def maybe_query(object_schema, args, fallback_fun)
      when not is_list(args) do
    maybe_query(object_schema, [args], fallback_fun)
  end

  def apply_error(error, args) do
    warn("Bonfire.Common.QueryModule - could not query: #{error} - Query args: #{inspect(args)}")

    nil
  end

  @doc "Get a Queryable identified by name or id."
  def query_module(query) when is_binary(query) or is_atom(query) do
    case query in modules() do
      true ->
        {:ok, query}

      _ ->
        case Bonfire.Common.SchemaModule.linked_query_modules()[query] ||
               Bonfire.Common.ContextModule.linked_query_modules()[query] do
          nil -> {:error, :not_found}
          module -> {:ok, module}
        end
    end
  end

  @doc "Look up a Queryable by name or id, throw :not_found if not found."
  def query_module!(query), do: Map.get(modules(), query) || throw(:not_found)

  @spec query_modules([binary | atom]) :: [binary]
  @doc "Look up many ids at once, throw :not_found if any of them are not found"
  def query_modules(modules) do
    Enum.map(modules, &Map.get(modules(), &1))
  end

  def maybe_query_module(query) do
    with {:ok, module} <- query_module(query) do
      # IO.inspect(maybe_query_module: module)
      module
    else
      _ ->
        Utils.maybe_apply(query, :query_module, [], &query_function_error/2)
    end
  end

  def query_function_error(error, _args, _level \\ :info) do
    warn(
      error,
      "QueryModule - there's no known query module for this schema, because one of: 1) No function query_module/0 on a context or schema module 1) No function schema_module/0 on a context or query module, that returns this schema's atom. 3)"
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

  def linked_schema_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules_cached(modules(), :schema_module)
  end

  def linked_context_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules_cached(modules(), :context_module)
  end
end
