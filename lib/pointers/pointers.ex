# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers do
  alias Pointers.Pointer
  alias Bonfire.Common.Pointers.Queries
  alias Pointers.NotFound

  import Bonfire.Common.Config, only: [repo: 0]
  require Logger

  def get!(id, filters \\ []) do
    with {:ok, obj} <- get(id, filters) do
      obj
    else _e ->
      raise NotFound
    end
  end

  def get(id, filters \\ [])

  def get(id, filters) when is_binary(id) do
    with {:ok, pointer} <- one(id: id) do
      get(pointer, filters)
    end
  end

  def get(%Pointer{} = pointer, filters) do
    with %{id: _} = obj <- follow!(pointer, filters) do
      {:ok, obj}
    end
  rescue
    NotFound -> {:error, :not_found}
  end

  def get(%{} = thing, _) do
    thing
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

  def many(filters \\ []), do: {:ok, repo().all(Queries.query(Pointer, filters))}

  # already have a pointer - just return it
  def maybe_forge!(%Pointer{} = pointer), do: pointer

  # for ActivityPub objects (like ActivityPub.Actor)
  def maybe_forge!(%{pointer_id: pointer_id} = _ap_object), do: one!(id: pointer_id)

  # forge a pointer
  def maybe_forge!(%{__struct__: _} = pointed), do: forge!(pointed)

  @doc """
  Retrieves the Table that a pointer points to
  Note: Throws an error if the table cannot be found
  """
  @spec table!(Pointer.t()) :: Table.t()
  def table!(%Pointer{table_id: id}), do: Pointers.Tables.table!(id)

  @doc """
  Forge a pointer from a structure that participates in the meta abstraction.

  Does not hit the database.

  Is safe so long as the provided struct participates in the meta abstraction.
  """
  @spec forge!(%{__struct__: atom, id: binary}) :: %Pointer{}
  def forge!(%{__struct__: table_id, id: id} = pointed) do
    #IO.inspect(forge: pointed)
    table = Pointers.Tables.table!(table_id)
    %Pointer{id: id, table: table, table_id: table.id, pointed: pointed}
  end

  @doc """
  Forges a pointer to a participating meta entity.

  Does not hit the database, is safe so long as the entry we wish to
  synthesise a pointer for represents a legitimate entry in the database.
  """
  @spec forge!(table_id :: integer | atom, id :: binary) :: %Pointer{}
  def forge!(table_id, id) do
    table = Pointers.Tables.table!(table_id)
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

  defp loader(schema, id_filters, override_filters) when not is_atom(schema) do
    loader(Pointers.Tables.schema!(schema), id_filters, override_filters)
  end

  defp loader(schema, id_filters, override_filters) do
    #IO.inspect(schema: schema)
    query_module = Bonfire.Contexts.run_module_function(schema, :queries_module, [], &query_pointer_function_error/2)
    case query_module do
      {:error, _} ->

        filters = id_filters ++ override_filters

        Logger.warn("Pointers.preload!: Attempting cowboy query on #{schema} with filters: #{inspect filters}")

        import Ecto.Query

        query = from l in schema,
          where: ^filters

        {:ok, repo().all(query)}

      _ ->
        filters = filters(schema, id_filters, override_filters)
        #IO.inspect(filters)
        query = Bonfire.Contexts.run_module_function(query_module, :query, [schema, filters])
        {:ok, repo().all(query)}
    end
  end

  def query_pointer_function_error(error, args, level \\ :warn) do
    Logger.log(level, "Pointers.preload!: #{error} with args: (#{inspect args})")

    {:error, error}
  end

  defp filters(schema, id_filters, []) do
    id_filters ++ Bonfire.Contexts.run_module_function(schema, :follow_filters, [])
  end

  defp filters(_schema, id_filters, override_filters) do
    id_filters ++ override_filters
  end

  @doc "Lists all that Pointers knows about"
  def list_all(), do: Pointers.Tables.data()

  def list_pointable_schemas() do
    pointable_tables = list_all()

    Enum.reduce(pointable_tables, [], fn {_id, x}, acc ->
      Enum.concat(acc, [x.schema])
    end)
  end

end
