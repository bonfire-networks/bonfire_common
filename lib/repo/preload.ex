defmodule Bonfire.Common.Repo.Preload do
  @moduledoc """
  Preload helpers for Ecto Repo
  """

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Cache

  use Ecto.Repo,
    otp_app: Bonfire.Common.Config.get!(:otp_app),
    adapter: Ecto.Adapters.Postgres

  # import Ecto.Query
  import Untangle
  use Arrows

  alias Pointers.Pointer
  alias Bonfire.Common.Pointers

  # def maybe_preload(obj, :context) do
  # # follow the context Pointer
  #   CommonsPub.Contexts.prepare_context(obj)
  # end

  def maybe_preload(obj, preloads, opts \\ [])

  def maybe_preload({:ok, obj}, preloads, opts), do: {:ok, maybe_preload(obj, preloads, opts)}

  def maybe_preload(%{edges: list} = page, preloads, opts) when is_list(list), do: Map.put(page, :edges, maybe_preload(list, preloads, opts))

  def maybe_preload(obj, preloads, false = follow_pointers?), do: maybe_preload(obj, preloads, follow_pointers: false) # deprecate

  def maybe_preload(obj, preloads, opts) when is_struct(obj) or is_list(obj) and is_list(opts) do

    if Keyword.get(opts, :follow_pointers, true) do
      debug("maybe_preload: trying to preload (and follow pointers): #{inspect preloads}")
      try_repo_preload(obj, preloads, opts)
      |> Pointers.Preload.maybe_preload_pointers(preloads, opts)

      # TODO: cache this as well (only if not needing to double check pointer boundaries)

    else
      debug("maybe_preload: trying to preload (without following pointers): #{inspect preloads}")

      obj = if Keyword.get(opts, :with_cache, false) do
        maybe_preload_from_cache(obj, preloads, opts)
      else
        try_repo_preload(obj, preloads, opts)
      end
    end
  end

  def maybe_preload(obj, _, _) do
    debug("maybe_preload: can only preload from struct or list of structs")

    obj
  end

  defp maybe_preload_from_cache(obj, preloads, opts) when is_list(obj) do
    Enum.map(obj, &maybe_preload_from_cache(&1, preloads, opts))
  end
  defp maybe_preload_from_cache(%{id: id} = obj, preloads, opts) when is_struct(obj) do
    opts
    |> Keyword.put_new(:cache_key, "preload:#{id}:#{inspect preloads}") # FIXME: some opts should also be included in key
    |> Cache.maybe_apply_cached(&try_repo_preload/3, [obj, preloads, opts], ...)
    # |> debug("preloads from cache")
  end

  defp try_repo_preload(%Ecto.Association.NotLoaded{}, _, _), do: nil

  defp try_repo_preload(obj, preloads, opts) when is_struct(obj) or is_list(obj) do
    repo().preload(obj, preloads, opts)
  rescue
    e in ArgumentError ->
      info(preloads, "maybe_preload skipped due to wrong argument: #{inspect e}")
      obj
    e ->
      warn("maybe_preload skipped with rescue: #{inspect e}")
      obj
  catch
    :exit, e ->
      warn("maybe_preload skipped with exit: #{inspect e}")
    e ->
      warn("maybe_preload skipped with catch: #{inspect e}")
  end

  defp try_repo_preload(obj, _, _), do: obj


  def maybe_preloads_per_nested_schema(objects, path, preloads, opts \\ [])

  def maybe_preloads_per_nested_schema(objects, path, preloads, opts) when is_list(objects) and is_list(path) and is_list(preloads) do
    debug("maybe_preloads_per_nested_schema iterate list of preloads")
    preloads
    |> Enum.reduce(objects, &maybe_preloads_per_nested_schema(&2, path, &1, opts))
  end

  def maybe_preloads_per_nested_schema(objects, path, {schema, preloads}, opts) when is_list(objects) do
    debug("maybe_preloads_per_nested_schema try schema: #{inspect schema} in path: #{inspect path} with preload: #{inspect preloads}")

    with {_old, loaded} <- get_and_update_in(
      objects,
      [Access.all()] ++ Enum.map(path, &Access.key!(&1)),
      &{&1, maybe_preloads_per_schema(&1, {schema, preloads}, opts)})
    do
      loaded
      # |> debug("preloaded")
    end
  end

  def maybe_preloads_per_nested_schema(object, _, _, _opts), do: object

  def maybe_preloads_per_schema(object, schema_preloads, opts \\ [])

  def maybe_preloads_per_schema(%Pointer{table_id: table_id} = object, {preload_schema, preloads}, opts) do
    object_schema = Bonfire.Common.Types.object_type(object)
    if object_schema==preload_schema do
      debug(preload_schema, "maybe_preloads_per_schema preloading schema for Pointer: #{inspect table_id}")
      object
      |> Pointers.follow!()
      |> try_repo_preload(preloads, opts)
      # TODO: make one preload per type to avoid n+1
    else
      object
    end
  end

  def maybe_preloads_per_schema(%{__struct__: object_schema} = object, {preload_schema, preloads}, opts) when object_schema==preload_schema do
    debug("maybe_preloads_per_schema preloading schema: #{inspect preload_schema}")
    try_repo_preload(object, preloads, opts)
    # TODO: make one preload per type to avoid n+1
  end

  def maybe_preloads_per_schema(object, _, _opts), do: object


end
