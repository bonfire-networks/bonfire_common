# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers do

  use OK.Pipe
  require Logger
  import Ecto.Query

  import Bonfire.Common.Config, only: [repo: 0]
  import Bonfire.Common.Extend
  import_if_enabled Bonfire.Boundaries.Queries

  alias Pointers.Pointer
  alias Bonfire.Common.Pointers.Queries
  alias Pointers.NotFound
  alias Bonfire.Common.Utils
  alias Bonfire.Common.ContextModules

  def get!(id, opts \\ []) do
    with {:ok, obj} <- get(id, opts) do
      obj
    else _e ->
      raise NotFound
    end
  end

  def get(id, opts \\ [])

  def get({:ok, by}, opts), do: get(by, opts)
  def get(%{pointer_id: by}, opts), do: get(by, opts)

  def get(id, opts) when is_binary(id) do
    with {:ok, pointer} <- one(id, opts) do
      get(pointer, opts)
    end
  end

  def get(%Pointer{} = pointer, opts) do
    with %{id: _} = obj <- follow!(pointer, opts) do
      {:ok,
        Utils.maybe_merge_to_struct(obj, pointer) # adds any assocs preloaded on pointer to the returned object
        #|> IO.inspect(label: "Pointers.get")
      }
    else e ->
      Logger.debug("Pointers: could not get: #{inspect e}")
      {:error, :not_found}
    end
  rescue
    NotFound -> {:error, :not_found}
  end

  def get(_, _) do
    {:error, :not_found}
  end

  def one(id, opts \\ [])

  def one(id, opts) when is_binary(id) do
    if Bonfire.Common.Utils.is_ulid?(id) do
      one([id: id], opts)
    else
      {:error, :not_found}
    end
  end

  # TODO: boundary check by default in one and many?

  def one(filters, opts), do: pointer_query(filters, opts) |> repo().single()

  def one!(filters, opts \\ []), do: pointer_query(filters, opts) |> repo().one!()

  def list!(pointers)
      when is_list(pointers) and length(pointers) > 0 and is_struct(hd(pointers)) do
    # means we're already being passed pointers? instead of ids
    Pointers.follow!(pointers)
  end

  def list!(ids) when is_list(ids) and length(ids) > 0 and is_binary(hd(ids)) do
    with {:ok, ptrs} <- many!(id: List.flatten(ids)), do: Pointers.follow!(ptrs)
  end

  def many(filters \\ [], opts \\ []), do: {:ok, pointer_query(filters, opts) |> repo().many() }
  def many!(filters \\ [], opts \\ []), do: pointer_query(filters, opts) |> repo().many()


  defp pointer_query(filters, opts) do

    q = Queries.query(nil, filters)

    if is_list(opts) && Keyword.get(opts, :skip_boundary_check) do
      Logger.info("Pointers: query with filters: #{inspect filters} and NO boundary check (because of opts.skip_boundary_check)")

      q

    else
      Logger.info("Pointers: query with filters: #{inspect filters} + boundary check (if Bonfire.Boundaries extension available)")

      Utils.maybe_apply(Bonfire.Boundaries.Queries, :object_only_visible_for, [q, opts], q)
    end
  end


  # already have a pointer - just return it
  def maybe_forge!(%Pointer{} = pointer), do: pointer

  # for ActivityPub objects (like ActivityPub.Actor)
  def maybe_forge!(%{pointer_id: pointer_id} = _ap_object), do: one!(id: pointer_id)

  # forge a pointer
  def maybe_forge!(%{__struct__: _} = pointed), do: forge!(pointed)

  @doc """
  Forge a pointer from a structure that participates in the meta abstraction.

  Does not hit the database.

  Is safe so long as the provided struct participates in the meta abstraction.
  """
  @spec forge!(%{__struct__: atom, id: binary}) :: %Pointer{}
  def forge!(%{__struct__: schema, id: id} = pointed) do
    #IO.inspect(forge: pointed)
    table = Bonfire.Common.Pointers.Tables.table!(schema)
    %Pointer{id: id, table: table, table_id: table.id, pointed: pointed}
  end

  @doc """
  Forges a pointer to a participating meta entity.

  Does not hit the database, is safe so long as the entry we wish to
  synthesise a pointer for represents a legitimate entry in the database.
  """
  @spec forge!(table_id :: integer | atom, id :: binary) :: %Pointer{}
  def forge!(table_id, id) do
    table = Bonfire.Common.Pointers.Tables.table!(table_id)
    %Pointer{id: id, table: table, table_id: table.id}
  end

  def follow!(pointer_or_pointers, opts \\ []) do
    case preload!(pointer_or_pointers, opts) do
      %Pointer{} = pointer -> pointer.pointed
      pointers -> Enum.map(pointers, & &1.pointed)
    end
  end

  @spec preload!(Pointer.t() | [Pointer.t()]) :: Pointer.t() | [Pointer.t()]
  @spec preload!(Pointer.t() | [Pointer.t()], list) :: Pointer.t() | [Pointer.t()]

  @doc """
  Follows one or more pointers and adds the pointed records to the `pointed` attrs
  """
  def preload!(pointer_or_pointers, opts \\ [])

  def preload!(%Pointer{id: id, table_id: table_id} = pointer, opts) do
    #IO.inspect(pointer)

    if is_nil(pointer.pointed) or Keyword.get(opts, :force) do
      with {:ok, [pointed]} <- loader(table_id, [id: id], opts) do
        %{pointer | pointed: pointed}
      else e ->
        Logger.debug("Pointers: could not load: #{inspect e}")
        pointer
      end
    else
      pointer
    end
  end

  # def preload!(pointers, opts, opts) when is_list(pointers) and length(pointers)==1, do: preload!(hd(pointers), opts, opts)

  def preload!(pointers, opts) when is_list(pointers) do
    pointers
    |> preload_load(opts)
    |> preload_collate(pointers)
  end

  def preload!(%{__struct__: _} = pointed, _), do: pointed

  defp preload_collate(loaded, pointers), do: Enum.map(pointers, &collate(loaded, &1))

  defp collate(_, nil), do: nil
  defp collate(loaded, %{} = p), do: %{p | pointed: Map.get(loaded, p.id, %{})}

  defp preload_load(pointers, opts) do
    force = Keyword.get(opts, :force, false)

    pointers
    # find ids
    |> Enum.reduce(%{}, &preload_search(force, &1, &2))
    # query
    |> Enum.reduce(%{}, &preload_per_table(&1, &2, opts))
  end

  defp preload_search(false, %{pointed: pointed}, acc)
       when not is_nil(pointed),
       do: acc

  defp preload_search(_force, pointer, acc) do
    ids = [pointer.id | Map.get(acc, pointer.table_id, [])]
    Map.put(acc, pointer.table_id, ids)
  end

  defp preload_per_table({table_id, ids}, acc, opts) do
    {:ok, items} = loader(table_id, [id: ids], opts)
    Enum.reduce(items, acc, &Map.put(&2, &1.id, &1))
  end

  defp loader(schema, id_filters, opts) when is_atom(schema), do: loader_query(schema, id_filters, opts)

  defp loader(table_id, id_filters, opts) do
    Bonfire.Common.Pointers.Tables.schema_or_table!(table_id) #|> IO.inspect
    |> loader_query(id_filters, opts)
  end

  defp loader_query(schema, id_filters, opts) when is_atom(schema) do
    query = query(schema, id_filters, opts)
    Logger.debug("Pointers: query with #{inspect query}")

    {:ok, query |> repo().many() }
  end

  defp loader_query(table_name, id_filters, opts) when is_binary(table_name) do
    Logger.debug("Pointers: loading data from a table without a schema module")
    table_name
    |> select(^Bonfire.Common.Pointers.Tables.table_fields(table_name))
    |> cowboy_query_all(id_binary(id_filters), opts)
    |> Utils.maybe_convert_ulids()
  end

  defp cowboy_query_all(schema_or_query, id_filters, opts) do

    {:ok, cowboy_query(schema_or_query, id_filters, opts) |> repo().many() }
  end

  defp cowboy_query(schema, id_filters, opts) when is_atom(schema) do
    schema
    (from m in schema, as: :main_object)
    |> cowboy_query(id_filters, opts)
  end

  defp cowboy_query(schema_or_query, id_filters, opts) do

    filters_override = Keyword.get(opts, :filters_override, [])
    filters = id_filters ++ filters_override

    if filters_override && filters_override !=[] do
      Logger.info("Pointers: Attempting cowboy query on #{inspect schema_or_query} with filters: #{inspect filters} (provided by opts.filters_override)")

      schema_or_query
      |> where(^filters_override)
      |> id_filter(id_filters)
      # |> IO.inspect
    else
      if is_list(opts) && Keyword.get(opts, :skip_boundary_check) do
        Logger.info("Pointers: Attempting cowboy query on #{inspect schema_or_query} with filters: #{inspect filters} and NO boundary check (because of opts.skip_boundary_check)")

        schema_or_query
        |> id_filter(id_filters)
        # |> IO.inspect
      else
        Logger.info("Pointers: Attempting cowboy query on #{inspect schema_or_query} with filters: #{inspect filters} + boundary check (if Bonfire.Boundaries extension available)")

        Utils.maybe_apply(Bonfire.Boundaries.Queries, :object_only_visible_for, [schema_or_query, opts], schema_or_query)
          |> where(^filters_override)
          |> id_filter(id_filters)
          # |> IO.inspect
      end
    end
  end

  def query(schema, filters, opts \\ [])

  def query(schema, %{context: context} = filters, opts) do
    query(schema, Map.drop(filters, [:context]), opts ++ [context: context])
  end

  def query(schema, filters, opts) when is_atom(schema) and is_list(filters) do
      query = case Bonfire.Common.QueryModules.maybe_query(schema, [filters(schema, filters, opts), opts]) do
      query when not is_nil(query) ->
        Logger.info("Pointers: using the QueryModule associated with #{schema}")

        query
        # |> IO.inspect

      _ ->

        cowboy_query(schema, filters, opts)
    end
  end

  def query(schema, filters, opts) when is_atom(schema) and is_map(filters) do
      query(schema, Map.to_list(filters), opts)
  end


  def id_filter(query, [id: ids]) when is_list(ids) do
    query
    |> where([p], p.id in ^ids)
  end
  def id_filter(query, [id: id]) when is_binary(id) do
    query
    |> where([p], p.id == ^id)
  end
  def id_filter(query, [paginate: pagination]) do
    limit = pagination[:limit] || 10

    query
    |> limit(^limit)
    # TODO: support pagination (before/after)
  end
  def id_filter(query, id) when is_binary(id) do
    query
    |> where([p], p.id == ^id)
  end
  def id_filter(query, [filter]) when is_tuple(filter) do
    # TODO: support several filters
    with {field, val} <- filter do
      query
      |> where([p], field(p, ^field) == ^val)
    end
  end
  def id_filter(query, []) do
    query
  end

  def id_binary([id: id]) do
    [id: id_binary(id)]
  end
  def id_binary([id: ids]) when is_list(ids) do
    [id: Enum.map(ids, &id_binary/1)]
  end
  def id_binary(id) when is_binary(id) do
    with {:ok, ulid} <- Pointers.ULID.dump(id), do: ulid
  end


  def filters(schema, id_filters, opts \\ []) do
    filters_override = Keyword.get(opts, :filters_override, [])

    if filters_override && filters_override !=[] do
      id_filters ++ filters_override
    else
      id_filters ++ follow_filters(schema)
    end
  end

  defp follow_filters(schema) do
    with {:error, _} <- Utils.maybe_apply(schema, :follow_filters, [], &follow_function_error/2),
         {:error, _} <- ContextModules.maybe_apply(schema, :follow_filters, [], &follow_function_error/2) do
        Logger.log(:warn, "Pointers.follow - there's no follow_filters/0 function declared on the pointable schema or its context module")
        # TODO: apply a boundary check by default?
      []
    end
  end

  def follow_function_error(error, _args, level \\ :info) do
    Logger.log(level, error)
    {:error, error}
  end

  def list_ids do
    many(select: [:id]) ~>> Enum.map(& &1.id)
  end

  @doc """
  Batch loading of associations for GraphQL API
  """
  def dataloader(context) do
    Dataloader.Ecto.new(repo(),
      query: &Bonfire.Common.Pointers.query/2,
      default_params: %{context: context}
    )
  end

end
