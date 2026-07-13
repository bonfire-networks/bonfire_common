defmodule Bonfire.Common.Repo.Preload do
  @moduledoc """
  Helpers for preloading Ecto struct associations
  """

  use Bonfire.Common.E
  import Bonfire.Common.Config, only: [repo: 0]
  # alias Bonfire.Common.Utils
  alias Bonfire.Common.Cache

  use Bonfire.Common.Repo

  # import Ecto.Query
  import Untangle
  use Arrows

  alias Needle.Pointer
  # alias Needle.Tables
  alias Bonfire.Common.Needles

  @doc """
  Preloads all associations for a given Ecto struct.

  ## Examples

      iex> preload_all(some_struct)
  """
  def preload_all(%{} = structure, opts \\ []) do
    for({key, %Ecto.Association.NotLoaded{}} <- Map.from_struct(structure), do: key)
    |> maybe_preload(structure, ..., opts)
  end

  @doc """
  Preloads mixin associations for a given Ecto struct.

  ## Examples

      iex> preload_mixins(some_struct)
  """
  def preload_mixins(%{} = structure, opts \\ []) do
    maybe_preload(structure, Needles.Tables.schema_mixins_not_loaded(structure), opts)
  end

  # def maybe_preload(obj, :context) do
  # # follow the context Pointer
  #   CommonsPub.Contexts.prepare_context(obj)
  # end

  @doc """
  Conditionally preloads associations based on provided options.

  ## Options

    * `:prune` - when the preload list is a deliberate superset across possible schemas, pass `prune: true` to fit it to the actual schema(s) upfront via reflection (invalid entries are dropped quietly instead of raising)
    * `:skip_err` - only warn (instead of `err`, which raises in test env) when a batch preload
      raises and gets recovered
    * `:follow_pointers` - set false to avoid following pointers
    * `:with_cache` - cache preload results (only with `follow_pointers: false`)

  ## Examples

      iex> maybe_preload(some_struct, [:assoc1, :assoc2])
      %{...}

      iex> maybe_preload({:ok, some_struct}, [:assoc1, :assoc2])
      {:ok, %{...}}
  """
  def maybe_preload(obj, preloads, opts \\ [])

  def maybe_preload({:ok, obj}, preloads, opts),
    do: {:ok, maybe_preload(obj, preloads, opts)}

  def maybe_preload(%{edges: list} = page, preloads, opts) when is_list(list),
    do: Map.put(page, :edges, maybe_preload(list, preloads, opts))

  # deprecate
  def maybe_preload(obj, preloads, false = _follow_pointers?),
    do: maybe_preload(obj, preloads, follow_pointers: false)

  def maybe_preload(obj, preloads, opts)
      when is_struct(obj) or (is_list(obj) and is_list(opts)) do
    if Keyword.get(opts, :follow_pointers, true) do
      debug(
        preloads,
        "maybe_preload #{opts[:label]}: trying to preload (and follow pointers)"
      )

      try_repo_preload(obj, preloads, opts)
      # TODO: use maybe_preload_nested_pointers instead of maybe_preload_pointers ? (but note the difference in key format)
      # |> Needles.Preload.maybe_preload_nested_pointers(preloads, opts)
      |> Needles.Preload.maybe_preload_pointers(preloads, opts)

      # TODO: cache this as well (only if not needing to double check pointer boundaries)
    else
      if Keyword.get(opts, :with_cache, false) do
        debug(
          preloads,
          "maybe_preload #{opts[:label]}: trying to preload using cache (without following pointers)"
        )

        maybe_preload_from_cache(obj, preloads, opts)
      else
        debug(
          preloads,
          "maybe_preload #{opts[:label]}: trying to preload (without using cache or following pointers)"
        )

        try_repo_preload(obj, preloads, opts)
      end
    end
  end

  def maybe_preload(obj, _, opts) do
    debug("#{e(opts, :label, nil)}: can only preload from struct or list of structs")

    obj
  end

  defp maybe_preload_from_cache(obj, preloads, opts) when is_list(obj) do
    Enum.map(obj, &maybe_preload_from_cache(&1, preloads, opts))
  end

  defp maybe_preload_from_cache(%{id: id} = obj, preloads, opts)
       when is_struct(obj) do
    opts
    # FIXME: some opts should also be included in key
    |> Keyword.put_new(:cache_key, "preload:#{id}:#{inspect(preloads)}")
    |> Cache.maybe_apply_cached(&try_repo_preload/3, [obj, preloads, opts], ...)

    # |> debug("preloads from cache")
  end

  defp try_repo_preload(%Ecto.Association.NotLoaded{}, _, _), do: nil
  defp try_repo_preload(%Ecto.Changeset{} = object, _, _), do: object

  defp try_repo_preload(objects, preloads, opts)
       when is_struct(objects) or is_list(objects) do
    debug(
      # preloads,
      "maybe_preload: trying Ecto.Repo.preload"
    )

    # `prune: true` — for call sites whose preload list is a deliberate superset across possible
    # schemas: fit it to the actual schema(s) upfront via reflection, so nothing raises. On a
    # heterogeneous list this must split per schema FIRST (each subset pruned to its own schema's
    # assocs) — pruning the mixed list to the intersection could silently drop everything, and
    # batch-preloading it would raise anyway (Ecto requires a homogeneous list).
    heterogeneous? = heterogeneous?(objects)
    prune? = opts[:prune]

    # explicit `try` (not a function-level rescue) so the bindings above stay visible in `rescue`
    try do
      cond do
        prune? && heterogeneous? ->
          recover_preload(objects, preloads, true, opts)

        prune? ->
          repo().preload(
            objects,
            prune_preloads(object_schemas(objects), List.wrap(preloads)),
            opts
          )

        true ->
          repo().preload(objects, preloads, opts)
      end
    rescue
      e in ArgumentError ->
        # A single invalid (sub-)assoc makes the whole batch `Repo.preload` raise, and a
        # heterogeneous list makes it raise outright (Ecto requires a homogeneous list). Recover by
        # preloading the valid subset (split per schema when heterogeneous) instead of dropping
        # everything. A mixed-struct list is legitimate in Bonfire (pointers!), so it only warns;
        # an invalid-assoc list is a bug at its source, so `err` raises in test env to get it fixed
        # there — pass `skip_err: true` to only warn (used by the recovery tests).
        msg =
          "batch preload raised; recovering by preloading only the valid entries: #{inspect(preloads)}"

        cond do
          opts[:skip_err] ->
            warn(e.message, msg)

          heterogeneous? ->
            err(
              e.message,
              msg <>
                " (heterogeneous list: can batch per schema but fix the call site or pass `prune: true` to filter the list to the actual schema(s))"
            )

          true ->
            err(
              e.message,
              msg <>
                " (can skip invalid entries but fix the call site or pass `prune: true` to automatically group and filter the list to the actual schema(s))"
            )
        end

        recover_preload(objects, preloads, heterogeneous?, opts)
    catch
      :exit, e ->
        err(e, "skipped with exit: #{inspect(preloads)}")
        objects

      e ->
        err(e, "skipped with catch: #{inspect(preloads)}")
        objects
    end
  end

  defp try_repo_preload(obj, preloads, _) do
    err(preloads, "unsupported preloads, return original object(s)")
    obj
  end

  # Recovery path (only after a batch preload raised): a heterogeneous list can't be batch-preloaded
  # at all (Ecto requires a homogeneous list), so split it per schema, recover each subset, and
  # reassemble in the original order; a homogeneous batch goes straight to the prune-and-retry path.
  defp recover_preload(objects, preloads, true = _heterogeneous?, opts) do
    objects
    |> Enum.with_index()
    |> Enum.group_by(fn {obj, _i} -> object_schema(obj) end)
    |> Enum.flat_map(fn {_schema, entries} ->
      {objs, idxs} = Enum.unzip(entries)
      Enum.zip(recover_preload_batch(objs, preloads, opts), idxs)
    end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp recover_preload(objects, preloads, _not_heterogeneous?, opts),
    do: recover_preload_batch(objects, preloads, opts)

  # Prune the invalid (sub-)entries via schema REFLECTION (`__schema__(:association, name)` — no
  # queries), then run ONE `Repo.preload` with the valid subset, so one bad assoc doesn't drop the
  # rest and nothing is loaded twice.
  defp recover_preload_batch(objects, preloads, opts) do
    case prune_preloads(object_schemas(objects), List.wrap(preloads)) do
      [] ->
        objects

      pruned ->
        try do
          repo().preload(objects, pruned, opts)
        rescue
          _ -> objects
        end
    end
  end

  defp object_schema(%schema{}), do: schema
  defp object_schema(_), do: nil

  defp object_schemas(objects) do
    objects
    |> List.wrap()
    |> Enum.map(&object_schema/1)
    |> Enum.uniq()
  end

  # More than one distinct struct type in the list (nil entries aside) — `Repo.preload` refuses these
  defp heterogeneous?(objects) when is_list(objects) do
    objects |> object_schemas() |> Enum.reject(&is_nil/1) |> length() > 1
  end

  defp heterogeneous?(_), do: false

  # Keeps the entries whose assoc every schema in the (possibly heterogeneous) list defines,
  # recursing into nested preloads via each assoc's related schema.
  defp prune_preloads(schemas, entries) do
    Enum.flat_map(entries, fn
      assoc when is_atom(assoc) ->
        if known_assoc?(schemas, assoc), do: [assoc], else: []

      {assoc, nested} when is_atom(assoc) and (is_list(nested) or is_atom(nested)) ->
        related = known_assoc?(schemas, assoc) && related_schemas(schemas, assoc)

        cond do
          related == false ->
            []

          related == [] ->
            # can't resolve the nested schema (e.g. a through-assoc): keep the entry as-is; if its
            # nested part is what's invalid, the outer rescue returns the objects unchanged
            [{assoc, nested}]

          true ->
            case prune_preloads(related, List.wrap(nested)) do
              [] -> [assoc]
              valid_nested -> [{assoc, valid_nested}]
            end
        end

      other ->
        # entries we can't reflect on (queries, functions): keep them; the outer rescue copes
        [other]
    end)
  end

  defp known_assoc?(schemas, assoc) do
    schemas != [] and
      Enum.all?(schemas, fn schema ->
        is_atom(schema) and not is_nil(schema) and function_exported?(schema, :__schema__, 2) and
          not is_nil(schema.__schema__(:association, assoc))
      end)
  end

  # The related schema(s) an assoc points at, via the existing reflection helper (which returns
  # nil/false for shapes with no queryable, e.g. through-assocs).
  defp related_schemas(schemas, assoc) do
    schemas
    |> Enum.map(&Needles.Tables.maybe_assoc_module(assoc, &1))
    |> Enum.filter(&(is_atom(&1) and not is_nil(&1) and &1 != false))
    |> Enum.uniq()
  end

  @doc """
  Conditionally preloads associations for nested schemas.

  ## Examples

      iex> maybe_preloads_per_nested_schema(objects, path, preloads)
      [%{...}, %{...}]
  """
  def maybe_preloads_per_nested_schema(objects, path, preloads, opts \\ [])

  def maybe_preloads_per_nested_schema(object, _, [], _opts), do: object

  def maybe_preloads_per_nested_schema(objects, path, preloads, opts)
      when is_list(path) and is_list(preloads) do
    preloads
    |> debug("iterate list of preloads")
    |> Enum.reduce(
      objects,
      &maybe_preloads_per_nested_schema(&2, path, &1, opts)
    )
  end

  def maybe_preloads_per_nested_schema(objects, path, schema_and_or_preloads, opts)
      when is_list(path) and is_list(objects) do
    debug(
      path,
      "trying #{inspect(schema_and_or_preloads)} in path"
    )

    # Group objects by how much of the path they have
    grouped_objects = group_objects_by_path_depth(objects, path)

    # Process each group with a single preload operation per group
    processed_objects =
      Enum.flat_map(grouped_objects, fn {path_depth, group_objects} ->
        if path_depth == 0 do
          # No path available, return as-is
          group_objects
        else
          partial_path = Enum.take(path, path_depth)

          # FIXME: this is causing n+1 queries for bonfire_data_social_apactivity
          with {_old, loaded} <-
                 get_and_update_in(
                   group_objects,
                   [Access.all()] ++ Enum.map(partial_path, &Access.key(&1, %{})),
                   &{&1, maybe_preloads_per_schema(&1, schema_and_or_preloads, opts)}
                 ) do
            loaded
          end
        end
      end)
      |> Map.new(fn obj -> {Map.get(obj, :id), obj} end)

    # Reconstruct original order and include any objects that were not processed 
    Enum.map(objects, fn obj ->
      case Map.get(obj, :id) do
        nil -> obj
        id -> Map.get(processed_objects, id) || obj
      end
    end)
  end

  def maybe_preloads_per_nested_schema(%{edges: edges} = page, path, schema_and_or_preloads, opts) do
    %{
      page
      | edges:
          edges
          |> maybe_preloads_per_nested_schema(path, schema_and_or_preloads, opts)
    }
  end

  def maybe_preloads_per_nested_schema(%{} = object, path, schema_and_or_preloads, opts)
      when is_list(path) do
    path_depth = calculate_path_depth(object, path)

    if path_depth == 0 do
      object
    else
      partial_path = Enum.take(path, path_depth)

      with {_old, loaded} <-
             get_and_update_in(
               object,
               Enum.map(partial_path, &Access.key(&1, %{})),
               &{&1, maybe_preloads_per_schema(&1, schema_and_or_preloads, opts)}
             ) do
        loaded
      end
    end
  end

  def maybe_preloads_per_nested_schema(object, _, _, _opts), do: object

  # Group objects by how much of the path they have
  defp group_objects_by_path_depth(objects, path) do
    objects
    |> Enum.group_by(&calculate_path_depth(&1, path))
    |> Enum.sort_by(fn {depth, _} -> -depth end)

    # |> debug()
  end

  # Calculate how deep into the path an object can go
  defp calculate_path_depth(object, path) do
    path
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {key, index}, acc ->
      partial_path = Enum.take(path, index + 1)

      case get_in(object, partial_path) do
        nil -> {:halt, acc}
        %Ecto.Association.NotLoaded{} -> {:halt, acc}
        _ -> {:cont, index + 1}
      end
    end)
    |> debug()
  end

  @doc """
  Conditionally preloads associations for a schema.

  ## Examples

      iex> maybe_preloads_per_schema(some_struct, {Schema, [:assoc1, :assoc2]})

      iex> maybe_preloads_per_schema(pointer_struct, {PointerSchema, [:assoc1, :assoc2]})
  """
  def maybe_preloads_per_schema(object, schema_and_or_preloads, opts \\ [])

  def maybe_preloads_per_schema(
        %Pointer{table_id: table_id} = object,
        {preload_schema, preloads},
        opts
      ) do
    object_schema = Bonfire.Common.Types.object_type(object)

    if object_schema == preload_schema do
      if Needle.is_needle?(object_schema, [:virtual]) do
        debug("no need to follow virtuals, just applying preloads")

        try_repo_preload(object, preloads, opts)
        |> debug("preloads done")
      else
        debug(
          preload_schema,
          "preloading schema for Pointer: #{inspect(table_id)}"
        )

        object
        |> Needles.follow!()
        |> debug("followed")
        |> try_repo_preload(preloads, opts)
        |> debug("preloads done")

        # TODO: make one preload per type to avoid n+1
      end
    else
      object
    end
  end

  def maybe_preloads_per_schema(
        %{__struct__: object_schema} = object,
        {preload_schema, preloads},
        opts
      )
      when object_schema == preload_schema do
    debug("preloading schema: #{inspect(preload_schema)}")

    try_repo_preload(object, preloads, opts)

    # TODO: make one preload per type to avoid n+1
  end

  def maybe_preloads_per_schema(object, schema_preloads, opts)
      when is_list(schema_preloads) do
    debug("iterate list of preloads")

    Enum.reduce(
      schema_preloads,
      object,
      &maybe_preloads_per_schema(&2, &1, opts)
    )
  end

  def maybe_preloads_per_schema(
        %Pointer{table_id: table_id} = object,
        preload_schema,
        opts
      )
      when is_atom(preload_schema) do
    object_schema = Bonfire.Common.Types.object_type(object)

    if object_schema == preload_schema do
      if Needle.is_needle?(object_schema, [:virtual]) do
        debug("no need to follow virtuals")

        object
      else
        object
        |> Needles.follow!()
        |> debug("followed")
      end
    else
      object
    end
  end

  def maybe_preloads_per_schema(object, other, _opts) do
    debug(other, "skip")
    object
  end

  @doc """
  Follows any unresolved `%Needle.Pointer{}` values found at `path` within `objects`,
  skipping those whose schema role is `:virtual` or `:mixin` (which don't need a DB query).
  Also applies any explicit `preload_nested` schema/preload pairs (e.g. `{Schema, assocs}` tuples).
  Both are merged into one `maybe_preloads_per_nested_schema/4` call.
  """
  def maybe_follow_pointer_schemas(objects, path, preload_nested \\ [], opts \\ [])

  def maybe_follow_pointer_schemas(%{edges: edges} = page, path, preload_nested, opts) do
    %{page | edges: maybe_follow_pointer_schemas(edges, path, preload_nested, opts)}
  end

  def maybe_follow_pointer_schemas(objects, path, preload_nested, opts) when is_list(objects) do
    schemas = detect_pointer_schemas(objects, path, preload_nested)
    maybe_preloads_per_nested_schema(objects, path, preload_nested ++ schemas, opts)
  end

  def maybe_follow_pointer_schemas(object, path, preload_nested, opts) do
    schemas = detect_pointer_schemas([object], path, preload_nested)
    maybe_preloads_per_nested_schema(object, path, preload_nested ++ schemas, opts)
  end

  defp detect_pointer_schemas(objects, path, preload_nested) do
    already_covered =
      MapSet.new(preload_nested, fn
        {schema, _assocs} -> schema
        schema -> schema
      end)
      |> debug("already covered schemas in detect_pointer_schemas")

    objects
    |> Enum.flat_map(fn obj ->
      case get_in(obj, path) do
        %Pointer{table_id: table_id} ->
          case Needle.Tables.schema(table_id) do
            {:ok, schema} ->
              if MapSet.member?(already_covered, schema) or
                   Needle.Util.role(schema) in [:virtual, :mixin],
                 do: [],
                 else: [schema]

            _ ->
              []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> debug("dynamic pointer schemas to follow")
  end
end
