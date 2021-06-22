# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers do
  alias Pointers.Pointer
  alias Bonfire.Common.Pointers.Queries
  alias Pointers.NotFound
  import Ecto.Query
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  require Logger
  use OK.Pipe


  def get!(id, filters \\ []) do
    with {:ok, obj} <- get(id, filters) do
      obj
    else _e ->
      raise NotFound
    end
  end

  def get(id, filters \\ [])

  def get({:ok, by}, filters), do: get(by, filters)

  def get(id, filters) when is_binary(id) do
    with {:ok, pointer} <- one(id) do
      get(pointer, filters)
    end
  end

  def get(%Pointer{} = pointer, filters) do
    with %{id: _} = obj <- follow!(pointer, filters) do
      {:ok,
        Utils.maybe_merge_to_struct(obj, pointer) # adds any assocs preload on pointer to the returned object
        #|> IO.inspect(label: "Pointers.get")
      }
    end
  rescue
    NotFound -> {:error, :not_found}
  end

  def get(_, _) do
    {:error, :not_found}
  end

  def one(id) when is_binary(id) do
    if Bonfire.Common.Utils.is_ulid?(id) do
      one(id: id)
    else
      {:error, :not_found}
    end
  end

  def one(filters), do: repo().single(Queries.query(Pointer, filters))

  def one!(filters), do: repo().one!(Queries.query(Pointer, filters))

  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Pointer, filters))}

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

  def follow!(pointer_or_pointers, filters \\ []) do
    case preload!(pointer_or_pointers, [], filters) do
      %Pointer{} = pointer -> pointer.pointed
      pointers -> Enum.map(pointers, & &1.pointed)
    end
  end

  @spec preload!(Pointer.t() | [Pointer.t()]) :: Pointer.t() | [Pointer.t()]
  @spec preload!(Pointer.t() | [Pointer.t()], list) :: Pointer.t() | [Pointer.t()]

  @doc """
  Follows one or more pointers and adds the pointed records to the `pointed` attrs
  """
  def preload!(pointer_or_pointers, opts \\ [], filters \\ [])

  def preload!(%Pointer{id: id, table_id: table_id} = pointer, opts, filters) do
    #IO.inspect(pointer)

    if is_nil(pointer.pointed) or Keyword.get(opts, :force) do
      with {:ok, [pointed]} <- loader(table_id, [id: id], filters) do
        %{pointer | pointed: pointed}
      else _ ->
        pointer
      end
    else
      pointer
    end
  end

  # def preload!(pointers, opts, filters) when is_list(pointers) and length(pointers)==1, do: preload!(hd(pointers), opts, filters)

  def preload!(pointers, opts, filters) when is_list(pointers) do
    pointers
    |> preload_load(opts, filters)
    |> preload_collate(pointers)
  end

  def preload!(%{__struct__: _} = pointed, _, _), do: pointed

  defp preload_collate(loaded, pointers), do: Enum.map(pointers, &collate(loaded, &1))

  defp collate(_, nil), do: nil
  defp collate(loaded, %{} = p), do: %{p | pointed: Map.get(loaded, p.id, %{})}

  defp preload_load(pointers, opts, filters) do
    force = Keyword.get(opts, :force, false)

    pointers
    # find ids
    |> Enum.reduce(%{}, &preload_search(force, &1, &2))
    # query
    |> Enum.reduce(%{}, &preload_per_table(&1, &2, filters))
  end

  defp preload_search(false, %{pointed: pointed}, acc)
       when not is_nil(pointed),
       do: acc

  defp preload_search(_force, pointer, acc) do
    ids = [pointer.id | Map.get(acc, pointer.table_id, [])]
    Map.put(acc, pointer.table_id, ids)
  end

  defp preload_per_table({table_id, ids}, acc, filters) do
    {:ok, items} = loader(table_id, [id: ids], filters)
    Enum.reduce(items, acc, &Map.put(&2, &1.id, &1))
  end

  defp loader(schema, id_filters, override_filters) when is_atom(schema), do: loader_query(schema, id_filters, override_filters)

  defp loader(table_id, id_filters, override_filters) do
    Bonfire.Common.Pointers.Tables.schema_or_table!(table_id) #|> IO.inspect
    |> loader_query(id_filters, override_filters)
  end

  defp loader_query(schema, id_filters, override_filters) when is_atom(schema) do
    # IO.inspect(loader_query_schema: schema)
    # TODO: make the query module configurable
    query = case Bonfire.Common.QueryModules.maybe_query(schema, filters(schema, id_filters, override_filters)) do
      query when not is_nil(query) ->

        query

      _ ->

        cowboy_query(schema, id_filters, override_filters)
    end

    {:ok, query |> repo().many() }
  end

  defp loader_query(table_name, id_filters, override_filters) when is_binary(table_name) do
    # load data from a table without a schema module
    table_name
    |> select(^Bonfire.Common.Pointers.Tables.table_fields(table_name))
    |> cowboy_query_all(id_binary(id_filters), override_filters)
    |> Utils.maybe_convert_ulids()
  end

  defp cowboy_query_all(schema_or_query, id_filters, override_filters) do

    {:ok, cowboy_query(schema_or_query, id_filters, override_filters) |> repo().many() }
  end

  defp cowboy_query(schema_or_query, id_filters, override_filters) do
    filters = id_filters ++ override_filters

    Logger.info("Pointers: Attempting cowboy query on #{inspect schema_or_query} with filters: #{inspect filters}")

    # TODO: check boundaries

    import Ecto.Query

    schema_or_query
      |> where(^override_filters)
      |> id_filter(id_filters)
      # |> IO.inspect

  end

  def id_filter(query, [id: ids]) when is_list(ids) do
    query
    |> where([p], p.id in ^ids)
  end
  def id_filter(query, [id: id]) when is_binary(id) do
    query
    |> where([p], p.id == ^id)
  end
  def id_filter(query, id) when is_binary(id) do
    query
    |> where([p], p.id == ^id)
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



  defp filters(schema, id_filters, []) do
    id_filters ++ follow_filters(schema)
  end

  defp filters(_schema, id_filters, override_filters) do
    id_filters ++ override_filters
  end

  defp follow_filters(schema) do
    with {:error, _} <- Utils.maybe_apply(schema, :follow_filters, [], &follow_function_error/2) do
      []
    end
  end

  def follow_function_error(error, _args, level \\ :info) do
    Logger.log(level, "Pointer.follow - there's no follow_filters/0 function declared for the pointable schema module #{error}")

    []
  end

  def list_ids do
    many(select: [:id]) ~>> Enum.map(& &1.id)
  end


end
