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
      debug(
        preloads,
        "maybe_preload #{opts[:label]}: trying to preload (without following pointers)"
      )

      if Keyword.get(opts, :with_cache, false) do
        maybe_preload_from_cache(obj, preloads, opts)
      else
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

  defp try_repo_preload(obj, preloads, opts)
       when is_struct(obj) or is_list(obj) do
    repo().preload(obj, preloads, opts)
  rescue
    e in ArgumentError ->
      warn(
        preloads,
        "skipped due to wrong argument: #{inspect(e)}"
      )

      # TODO: we should still preload the assocs that do exist when one in the list was invalid

      obj

    e ->
      warn(preloads, "skipped with rescue: #{inspect(e)} // attempted preloads")
      obj
  catch
    :exit, e ->
      error("skipped with exit: #{inspect(e)}")

    e ->
      error("skipped with catch: #{inspect(e)}")
  end

  defp try_repo_preload(obj, _, _), do: obj

  @doc """
  Conditionally preloads associations for nested schemas.

  ## Examples

      iex> maybe_preloads_per_nested_schema(objects, path, preloads)
      [%{...}, %{...}]
  """
  def maybe_preloads_per_nested_schema(objects, path, preloads, opts \\ [])

  def maybe_preloads_per_nested_schema(objects, path, preloads, opts)
      when is_list(path) and is_list(preloads) do
    debug("iterate list of preloads")

    Enum.reduce(
      preloads,
      objects,
      &maybe_preloads_per_nested_schema(&2, path, &1, opts)
    )
  end

  def maybe_preloads_per_nested_schema(objects, path, {schema, preloads}, opts)
      when is_list(objects) do
    debug(
      "try schema: #{inspect(schema)} in path: #{inspect(path)} with preload: #{inspect(preloads)}"
    )

    with {_old, loaded} <-
           get_and_update_in(
             objects,
             [Access.all()] ++ Enum.map(path, &Access.key!(&1)),
             &{&1, maybe_preloads_per_schema(&1, {schema, preloads}, opts)}
           ) do
      loaded

      # |> debug("preloaded")
    end
  end

  def maybe_preloads_per_nested_schema(%{} = object, path, {schema, preloads}, opts) do
    debug(
      "try schema: #{inspect(schema)} in path: #{inspect(path)} with preload: #{inspect(preloads)}"
    )

    with {_old, loaded} <-
           get_and_update_in(
             object,
             Enum.map(path, &Access.key!(&1)),
             &{&1, maybe_preloads_per_schema(&1, {schema, preloads}, opts)}
           ) do
      loaded

      # |> debug("preloaded")
    end
  end

  def maybe_preloads_per_nested_schema(object, _, _, _opts), do: object

  @doc """
  Conditionally preloads associations for a schema.

  ## Examples

      iex> maybe_preloads_per_schema(some_struct, {Schema, [:assoc1, :assoc2]})

      iex> maybe_preloads_per_schema(pointer_struct, {PointerSchema, [:assoc1, :assoc2]})
  """
  def maybe_preloads_per_schema(object, schema_preloads, opts \\ [])

  def maybe_preloads_per_schema(
        %Pointer{table_id: table_id} = object,
        {preload_schema, preloads},
        opts
      ) do
    object_schema = Bonfire.Common.Types.object_type(object)

    if object_schema == preload_schema do
      debug(
        preload_schema,
        "preloading schema for Pointer: #{inspect(table_id)}"
      )

      object
      |> Needles.follow!()
      |> try_repo_preload(preloads, opts)

      # TODO: make one preload per type to avoid n+1
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

  def maybe_preloads_per_schema(object, other, _opts) do
    debug(other, "skip")
    object
  end
end
