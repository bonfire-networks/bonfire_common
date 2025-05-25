# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Needles do
  @moduledoc "Helpers for handling `Needle` Pointers"

  use Arrows
  import Untangle
  use Bonfire.Common.E
  import Bonfire.Common.Config, only: [repo: 0]
  import Bonfire.Common.Extend
  import_if_enabled(Bonfire.Boundaries.Queries)
  import Ecto.Query
  import EctoSparkles
  alias Bonfire.Common.Needles.Pointers.Queries
  use Bonfire.Common.Utils
  alias Bonfire.Common.Cache
  alias Bonfire.Common.ContextModule
  alias Needle.NotFound
  alias Needle.Pointer
  # alias Needle.Tables

  @doc """
  Retrieves an object by its ID. Raises `NotFound` if the object cannot be found.

  ## Examples

      iex> Bonfire.Common.Needles.get!("existing_id")
      %Pointer{id: "existing_id", ...}

      iex> Bonfire.Common.Needles.get!("non_existent_id")
      ** (Needle.NotFound) ...
  """
  def get!(id, opts \\ []) do
    with {:ok, obj} <- get(id, opts) do
      obj
    else
      _e ->
        raise NotFound
    end
  end

  @doc """
  Retrieves an object by its ID.

  ## Examples

      iex> Bonfire.Common.Needles.get("existing_id")
      {:ok, %Pointer{id: "existing_id", ...}}

      iex> Bonfire.Common.Needles.get("non_existent_id")
      {:error, :not_found}
  """
  def get(id, opts \\ [])

  def get({:ok, by}, opts), do: get(by, opts)
  def get(%{pointer_id: by}, opts) when is_binary(by), do: get(by, opts)
  def get(id, opts) when is_binary(id), do: one(id, opts) ~> get(opts)

  def get(%Pointer{} = pointer, opts) do
    with %{id: _} = obj <- follow!(pointer, opts) do
      {:ok, obj}
    else
      e ->
        error(pointer, "Could not follow - #{inspect(e)}")
        # {:error, :not_found}
        {:ok, pointer}
    end
  rescue
    NotFound ->
      error("Pointer raised NotFound")
      {:ok, pointer}
  end

  # def get([%Pointer{}|_] = pointers, opts) do
  #   do_follow!(pointers, opts)
  # end

  def get(other, _) do
    error("Cannot get a pointer with #{inspect(other)}")
    {:error, :not_found}
  end

  @doc """
  Retrieves an object by its ID or pointer.

  ## Examples

      iex> Bonfire.Common.Needles.get("some_id")
      {:ok, %Pointer{id: "some_id", ...}}

      iex> Bonfire.Common.Needles.get([id: "some_id"])
      {:ok, %Pointer{id: "existing_id", ...}}
  """
  def one(id, opts \\ [])
  def one(id, opts) when is_binary(id), do: one(filter_one(id), opts)
  # TODO: boundary check by default in one and many?
  def one(filters, opts), do: pointer_query(filters, opts) |> repo().single()

  @doc """
  Retrieves a single object based on the provided filters with bang.

      iex> Bonfire.Common.Needles.one!("some_id")
      %Pointer{id: "some_id", ...}

      iex> Bonfire.Common.Needles.one!([id: "some_id"])
      %Pointer{id: "some_id", ...}
  """
  def one!(filters, opts \\ []),
    do: pointer_query(filters, opts) |> repo().one!()

  @doc """
  Checks if an object exists based on the given filters.

  ## Examples

      iex> Bonfire.Common.Needles.exists?("some_id")
      true

      iex> Bonfire.Common.Needles.exists?("non_existent_id")
      false
  """
  def exists?(filters, opts \\ [])

  def exists?(filters, opts) when is_binary(filters),
    do:
      filter_one(filters)
      |> pointer_query(opts ++ [skip_boundary_check: true])
      |> repo().exists?()

  def exists?(filters, opts),
    do:
      pointer_query(filters, opts ++ [skip_boundary_check: true])
      |> repo().exists?()

  @doc """
  Retrieves a list of objects based on pointers or IDs.

  ## Examples

      iex> Bonfire.Common.Needles.list!(["id1", "id2"])
      [%Pointer{id: "id1", ...}, %Pointer{id: "id2", ...}]

      iex> Bonfire.Common.Needles.list!([%Pointer{id: "id1"}, %Pointer{id: "id2"}])
      [%Pointer{id: "id1", ...}, %Pointer{id: "id2", ...}]
  """
  def list!(pointers, opts \\ [])

  def list!(pointers, opts)
      when is_list(pointers) and length(pointers) > 0 and
             is_struct(hd(pointers)) do
    # means we're already being passed pointers? instead of ids
    follow!(pointers, opts)
  end

  def list!(ids, opts) when is_list(ids) and length(ids) > 0 and not is_nil(hd(ids)) do
    with {:ok, ptrs} <- many!([id: List.flatten(ids)], opts), do: follow!(ptrs, opts)
  end

  def list!(ids, _opts) do
    warn("Needles.list: expected a list of pointers or ULIDs, got #{inspect(ids)}")

    []
  end

  @doc """
  Retrieves objects based on type and filters.

  ## Examples

      > Bonfire.Common.Needles.list_by_type!(:my_table, [filter: value])
      [%Pointer{...}, %Pointer{...}]
  """
  def list_by_type!(table_id_or_schema, filters \\ [], opts \\ []) do
    loader(table_id_or_schema, filters, opts)
  end

  @doc """
  Retrieves many objects based on the provided filters

  ## Examples

      > Bonfire.Common.Needles.many([id: "some_id"])
      {:ok, [%Pointer{id: "some_id", ...}]}

      > Bonfire.Common.Needles.many([id: "non_existing_id"])
      {:ok, []}
  """
  def many(filters \\ [], opts \\ []),
    do: {:ok, pointer_query(filters, opts) |> repo().many()}

  @doc """

  Retrieves many objects based on the provided filters

      iex> Bonfire.Common.Needles.many!([id: "some_id"])
      [%Pointer{id: "some_id", ...}]
  """
  def many!(filters \\ [], opts \\ []),
    do: pointer_query(filters, opts) |> repo().many()

  @doc """
  Filters a single pointer from a query result.

  ## Examples

      iex> Bonfire.Common.Needles.filter_one("http://url")
      [canonical_uri: "http://url"]
  """
  def filter_one(filters) do
    if Bonfire.Common.Types.is_uid?(filters) do
      [id: filters]
    else
      if String.starts_with?(filters, "http") do
        [canonical_uri: filters]
      else
        [username: filters]
      end
    end
  end

  @doc """
  Prepares a query for pointers.

  ## Examples

      > Bonfire.Common.Needles.pointer_query(query, opts)
      %Ecto.Query{...}

      > Bonfire.Common.Needles.pointer_query([id: "some_id"], opts)
      %Ecto.Query{...}
  """
  def pointer_query(%Ecto.Query{} = q, opts) do
    pointer_query_boundarise(q, opts)
  end

  def pointer_query(filters, opts) do
    if opts[:deleted] do
      Queries.query_incl_deleted()
    else
      Queries.query(Pointer)
    end
    # |> debug()
    |> Queries.query(filters)
    # |> debug()
    |> pointer_query_boundarise(opts)
  end

  defp pointer_query_boundarise(%Ecto.Query{} = q, opts) do
    opts =
      Utils.to_options(opts)

    # |> debug("opts")

    # note: cannot use boundarise macro to avoid dependency cycles
    Utils.maybe_apply(
      Bonfire.Boundaries.Queries,
      :object_boundarised,
      [q, opts],
      fallback_return: q
    )
    |> pointer_preloads(opts[:preload])

    # if e(opts, :log_query, nil), do: info(q), else: q
  end

  @doc """
  Preloads associations based on the given preloads option.

  ## Examples

      > Bonfire.Common.Needles.pointer_preloads(query, :with_creator)
      %Ecto.Query{...}

      > Bonfire.Common.Needles.pointer_preloads(query, :tags)
      %Ecto.Query{...}
  """
  def pointer_preloads(query, preloads) do
    case preloads do
      _ when is_list(preloads) ->
        Enum.reduce(preloads, query, &pointer_preloads(&2, &1))

      :with_creator ->
        proload(query,
          created: [
            creator:
              {"creator_",
               [
                 character: [
                   # :peered
                 ],
                 profile: [:icon]
               ]}
          ]
        )

      :profile_info ->
        proload(
          query,
          [:character, profile: :icon]
        )

      # Tags/mentions
      :tags ->
        proload(query,
          tags: [:character, profile: :icon]
        )

      :character ->
        proload(query, :character)

      :with_content ->
        proload(query, [:post_content, :peered])

      _default ->
        query
    end
  end

  @doc """
  Turns a thing into a pointer if it is not already or returns nil.

  ## Examples

      iex> Bonfire.Common.Needles.maybe_forge(%Pointer{id: "existing_id"})
      %Pointer{id: "existing_id"}

      iex> Bonfire.Common.Needles.maybe_forge(%{pointer_id: "existing_id"})
      %Pointer{id: "existing_id"}

      iex> Bonfire.Common.Needles.maybe_forge(%{id: "existing_id"})
      nil
  """
  def maybe_forge(%Pointer{} = thing), do: thing

  def maybe_forge(%{pointer_id: pointer_id}) when is_binary(pointer_id),
    do: one!(id: pointer_id)

  def maybe_forge(thing) when is_struct(thing),
    do: if(Needle.is_needle?(thing, [:pointable, :virtual]), do: forge!(thing))

  def maybe_forge(_), do: nil

  @doc """
  Turns a thing into a pointer if it is not already. Errors if it cannot be performed.

      iex> Bonfire.Common.Needles.maybe_forge!(%Pointer{id: "existing_id"})
      %Pointer{id: "existing_id"}

      iex> Bonfire.Common.Needles.maybe_forge!(%{pointer_id: "existing_id"})
      %Pointer{id: "existing_id"}

      iex> Bonfire.Common.Needles.maybe_forge!(%{id: "non_existing_id"})
      ** (RuntimeError) ...
  """
  def maybe_forge!(thing) do
    case {thing, Needle.is_needle?(thing, [:pointable, :virtual])} do
      {%Pointer{}, _} -> thing
      {%{}, true} -> forge!(thing)
      # for AP objects like ActivityPub.Actor
      {%_{pointer_id: pointer_id}, false} -> one!(id: pointer_id)
    end
  end

  @doc """
  Forge a pointer from a pointable object.

  Does not hit the database, is safe so long as the provided struct participates in the meta abstraction.

  ## Examples

      iex> Bonfire.Common.Needles.forge!(%{__struct__: MySchema, id: "some_id"})
      %Pointer{id: "some_id", ...}

  """
  @spec forge!(%{__struct__: atom, id: binary}) :: %Pointer{}
  def forge!(%{__struct__: schema, id: id} = pointed) do
    # debug(forge: pointed)
    table = Bonfire.Common.Needles.Tables.table!(schema)
    %Pointer{id: id, table: table, table_id: table.id, pointed: pointed}
  end

  @doc """
  Forges a pointer to a participating meta entity

  Does not hit the database, is safe so long as the entry we wish to
  synthesise a pointer for represents a legitimate entry in the database.

  ## Examples

      iex> Bonfire.Common.Needles.forge!(:my_table, "some_id")
      %Pointer{id: "some_id", ...}
  """
  @spec forge!(table_id :: integer | atom, id :: binary) :: %Pointer{}
  def forge!(table_id, id) do
    table = Bonfire.Common.Needles.Tables.table!(table_id)
    %Pointer{id: id, table: table, table_id: table.id}
  end

  @doc """
  Follows one or more pointers and returns the schema struct.

  ## Examples

      > Bonfire.Common.Needles.follow!(%Pointer{id: "some_id"})
      %SomeRecord{}

      > Bonfire.Common.Needles.follow!([%Pointer{id: "some_id"}])
      [%SomeRecord{}]
  """
  def follow!(pointer_or_pointers, opts \\ [])

  def follow!(%Pointer{table_id: table_id} = pointer, opts) do
    with {:ok, schema} <- Needle.Tables.schema(table_id),
         :virtual <- schema.__pointers__(:role) do
      # info(table_id, "virtual - skip following ")
      if function_exported?(schema, :__struct__, 0) do
        # debug("schema is available in the compiled app")
        struct(schema, Enums.struct_to_map(pointer))
      else
        debug("schema is not available in the compiled app")
        pointer
      end
    else
      _e ->
        # info(e, "not a virtual")
        do_follow!(pointer, opts)
    end
  end

  def follow!(pointers, opts) do
    do_follow!(pointers, opts)
  end

  defp do_follow!(pointer_or_pointers, opts) do
    case preload!(pointer_or_pointers, opts) do
      %{pointed: followed_pointer} ->
        debug("merge any assocs previously preloaded on pointer to the returned object")

        Enums.maybe_merge_to_struct(followed_pointer, pointer_or_pointers)

      followed_pointers when is_list(followed_pointers) ->
        Enum.map(followed_pointers, fn
          %{pointed: pointed} -> pointed
          other -> other
        end)
    end
  end

  @spec preload!(Pointer.t() | [Pointer.t()]) :: Pointer.t() | [Pointer.t()]
  @spec preload!(Pointer.t() | [Pointer.t()], list) ::
          Pointer.t() | [Pointer.t()]

  @doc """
  Follows one or more pointers and adds the pointed records to the `pointed` attrs.

      > Bonfire.Common.Needles.preload!(%Pointer{id: "some_id"})
      %Pointer{id: "some_id", pointed: %SomeRecord{}}

      > Bonfire.Common.Needles.preload!([%Pointer{id: "some_id"}])
      [%Pointer{id: "some_id", pointed: %SomeRecord{}}]
  """
  def preload!(pointer_or_pointers, opts \\ [])

  def preload!(%Pointer{id: id, table_id: table_id} = pointer, opts) do
    # debug(pointer)

    if is_nil(pointer.pointed) or Keyword.get(opts, :force) do
      case loader(table_id, [id: id], opts) do
        {:ok, [pointed]} ->
          %{pointer | pointed: pointed}

        [pointed] ->
          %{pointer | pointed: pointed}

        [] ->
          if opts[:skip_boundary_check] != true do
            error(
              "Needle: could not load #{id} from #{inspect(table_id)} (maybe because not allowed by boundaries)"
            )
          else
            debug("Needle: could not find #{id} from #{inspect(table_id)}")
          end

          pointer

        other ->
          debug(other, "Needle: could not load #{id} from #{inspect(table_id)}")
          pointer
      end
    else
      pointer
    end
  end

  # def preload!(pointers, opts, opts) when is_list(pointers) and length(pointers)==1, do: preload!(hd(pointers), opts, opts)

  def preload!(pointers, opts) when is_list(pointers) do
    # %{true: pointers, false: others} = Enum.group_by(pointers, & is_struct(&1, Pointer))

    pointers
    |> preload_load(opts)
    |> preload_collate(pointers)
  end

  def preload!(%{__struct__: _} = pointed, _), do: pointed

  defp preload_collate(loaded, pointers) when is_list(pointers),
    do: Enum.map(pointers, &collate(loaded, &1))

  defp collate(_, nil), do: nil
  defp collate(%{} = loaded, %Pointer{} = p), do: %{p | pointed: Map.get(loaded, p.id, %{})}
  defp collate(_, p), do: p

  defp preload_load(pointers, opts) when is_list(pointers) do
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

  defp preload_search(_force, %{id: id, table_id: table_id}, acc) do
    ids = [id | Map.get(acc, table_id, [])]
    Map.put(acc, table_id, ids)
  end

  defp preload_search(false, object, acc)
       when is_struct(object) or is_nil(object),
       do: acc

  defp preload_per_table({table_id, ids}, acc, opts) do
    with items when is_list(items) <- loader(table_id, [id: ids], opts) do
      Enum.reduce(items, acc, &Map.put(&2, &1.id, &1))
    end
  end

  defp loader(schema, id_filters, opts) when is_atom(schema),
    do: loader_query(schema, id_filters, opts)

  defp loader(table_id, id_filters, opts) do
    Cache.maybe_apply_cached(&Bonfire.Common.Needles.Tables.schema_or_table!/1, [table_id])
    |> loader_query(id_filters, opts)
  end

  defp loader_query(schema, id_filters, opts) when is_atom(schema) do
    query(schema, id_filters, opts)
    |> debug("Needle: query with")
    |> repo().many()
  end

  defp loader_query(table_name, id_filters, opts) when is_binary(table_name) do
    debug(table_name, "Needle: loading data from a table without a schema module")

    # Cache.maybe_apply_cached(&generic_loader_query/3, [table_name, id_filters, opts])

    from(m in table_name, as: :main_object)
    |> select(
      ^Cache.maybe_apply_cached(&Bonfire.Common.Needles.Tables.table_fields/1, [table_name])
    )
    # ++ [cache: true]
    |> generic_query_all(id_binary(id_filters), opts)
    |> Types.maybe_convert_ulids()
  end

  defp generic_query_all(schema_or_query, id_filters, opts) do
    generic_query(schema_or_query, id_filters, opts)
    |> repo().many()
  end

  defp generic_query(schema, id_filters, opts) when is_atom(schema) do
    from(m in schema, as: :main_object)
    |> generic_query(id_filters, opts)
  end

  defp generic_query(schema_or_query, id_filters, opts) do
    filters_override = Keyword.get(opts, :filters_override, [])
    filters = id_filters ++ filters_override

    if filters_override && filters_override != [] do
      debug(
        "Needle: Attempting a generic query on #{inspect(schema_or_query)} with filters: #{inspect(filters)} (provided by opts.filters_override)"
      )

      schema_or_query
      |> where(^filters_override)
      |> id_filter(id_filters)

      # |> IO.inspect
    else
      if is_list(opts) && Keyword.get(opts, :skip_boundary_check) do
        debug(
          "Needle: Attempting a generic query with NO boundary check (because of opts.skip_boundary_check) on #{inspect(schema_or_query)} with filters: #{inspect(filters)}"
        )

        id_filter(
          schema_or_query,
          id_filters
        )

        # |> IO.inspect
      else
        debug(
          "Needle: Attempting generic query on #{inspect(schema_or_query)} with filters: #{inspect(filters)} + boundary check (if Bonfire.Boundaries extension available)"
        )

        q =
          schema_or_query
          |> where(^filters_override)
          |> id_filter(id_filters)

        # |> IO.inspect

        # note: cannot use boundarise macro to avoid depedency cycles
        Utils.maybe_apply(
          Bonfire.Boundaries.Queries,
          :object_boundarised,
          [q, opts],
          fallback_return: q
        )
      end
    end
  end

  @doc """
  Queries a dataset based on provided filters.

  ## Examples

      > Bonfire.Common.Needles.query(filters)
      %Ecto.Query{...}
  """
  def query(schema, filters, opts \\ [])

  def query(schema, %{context: context} = filters, opts) do
    query(schema, Map.drop(filters, [:context]), opts ++ [context: context])
  end

  def query(schema, filters, opts) when is_atom(schema) and is_list(filters) do
    case Bonfire.Common.QueryModule.maybe_query(schema, [
           filters(schema, filters, opts),
           opts
         ]) do
      %Ecto.Query{} = query ->
        debug("Needle: using the QueryModule associated with #{schema}")

        query

      # |> IO.inspect

      _ ->
        generic_query(schema, filters, opts)
    end
  end

  def query(schema, filters, opts) when is_atom(schema) and is_map(filters) do
    query(schema, Map.to_list(filters), opts)
  end

  @doc """
  Filters an object by its ID.

  ## Examples

      iex> Bonfire.Common.Needles.id_filter(query, id: "some_id")
  """
  def id_filter(query, id: ids) when is_list(ids) do
    where(query, [p], p.id in ^ids)
  end

  def id_filter(query, id: id) when is_binary(id) do
    where(query, [p], p.id == ^id)
  end

  def id_filter(query, paginate: paginate) do
    limit = paginate[:limit] || 10

    limit(
      query,
      ^limit
    )

    # TODO: support pagination (before/after)
  end

  def id_filter(query, id) when is_binary(id) do
    where(query, [p], p.id == ^id)
  end

  def id_filter(query, [filter]) when is_tuple(filter) do
    # TODO: support several filters
    with {field, val} <- filter do
      where(query, [p], field(p, ^field) == ^val)
    end
  end

  def id_filter(query, []) do
    query
  end

  @doc """
  Filters an object by its binary ID.

  ## Examples

      iex> Bonfire.Common.Needles.id_binary(id: "some_id")
  """
  def id_binary(id: ids) when is_list(ids) do
    [id: Enum.map(ids, &id_binary/1)]
  end

  def id_binary(id: id) do
    [id: id_binary(id)]
  end

  def id_binary(id) when is_binary(id) do
    with {:ok, ulid} <- Needle.ULID.dump(id), do: ulid
  end

  @doc """
  Applies filters to a query.

  ## Examples

      iex> Bonfire.Common.Needles.filters(query, filters)
      %Ecto.Query{...}
  """
  def filters(schema, id_filters, opts \\ []) do
    filters_override = Keyword.get(opts, :filters_override, [])

    if filters_override && filters_override != [] do
      id_filters ++ filters_override
    else
      id_filters ++ follow_filters(schema)
    end
  end

  defp follow_filters(schema) do
    with {:error, _} <-
           Utils.maybe_apply(
             schema,
             :follow_filters,
             [],
             &follow_function_error/2
           ),
         {:error, _} <-
           ContextModule.maybe_apply(
             schema,
             :follow_filters,
             [],
             &follow_function_error/2
           ) do
      debug(
        schema,
        "Needle.follow - there's no follow_filters/0 function declared on the pointable schema or its context module"
      )

      # TODO: apply a boundary check by default?
      []
    end
  end

  def follow_function_error(error, _args) do
    debug(error)
    {:error, error}
  end

  @doc """
  Retrieves a list of known IDs 

  ## Examples

      iex> Bonfire.Common.Needles.list_ids()
      ["id1", "id2"]

  """
  def list_ids do
    many(select: [:id]) ~> Enum.map(& &1.id)
  end

  @doc """
  Resolves pointers for GraphQL API batch loading.

  ## Examples

      iex> Bonfire.Common.Needles.dataloader(context)
      %Dataloader{...}
  """
  def dataloader(context) do
    Dataloader.Ecto.new(repo(),
      query: &Bonfire.Common.Needles.query/2,
      default_params: %{context: context}
    )
  end

  @doc """
  Resolves associations or fields based on the given parent and context.

  ## Examples

      iex> Bonfire.Common.Needles.maybe_resolve(parent, field, args, context)
      {:ok, resolved_data}
  """
  def maybe_resolve(parent, field, args, context) do
    # WIP
    case Map.get(parent, field, :no_such_field) do
      %Ecto.Association.NotLoaded{} ->
        # dataloader(:source, :members).(parent, args, context)
        Absinthe.Resolution.Helpers.dataloader(Needle.Pointer).(parent, args, context)

      :no_such_field ->
        Absinthe.Resolution.Helpers.dataloader(Needle.Pointer).(parent, args, context)

      already_loaded ->
        {:ok, already_loaded}
    end
  end
end
