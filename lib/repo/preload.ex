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

    repo().preload(objects, preloads, opts)
  rescue
    e in ArgumentError ->
      error(
        e.message,
        "skipped preload due to wrong argument: #{inspect(preloads)}"
      )

      # TODO
      debug(
        objects,
        "returning non-preloaded object - TODO: we should still preload the assocs that do exist when one in the list was invalid"
      )

    e in ArgumentError ->
      error(
        e.message,
        "skipped preload due to wrong function clause: #{inspect(preloads)}"
      )

      # TODO
      debug(
        objects,
        "returning non-preloaded object - TODO: we should still preload the assocs that do exist when one in the list was invalid"
      )

    e ->
      error(e, "skipped preload with rescue: #{inspect(preloads)}")
      # TODO
      debug(
        objects,
        "returning non-preloaded object - TODO: we should still preload the assocs that do exist when one in the list was invalid"
      )
  catch
    :exit, e ->
      error(e, "skipped with exit: #{inspect(preloads)}")
      # TODO
      debug(
        objects,
        "returning non-preloaded object - TODO: we should still preload the assocs that do exist when one in the list was invalid"
      )

    e ->
      error(e, "skipped with catch: #{inspect(preloads)}")
      # TODO
      debug(
        objects,
        "returning non-preloaded object, but we should still preload the assocs that do exist when one in the list was invalid"
      )
  end

  defp try_repo_preload(obj, preloads, _) do
    warn(preloads, "unsupported preloads, return original object(s)")
    obj
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
end
