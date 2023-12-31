defmodule Bonfire.Common.Needles.Preload do
  # import Bonfire.Common.Config, only: [repo: 0]
  # alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  import Untangle

  def maybe_preload_pointers(object, keys, opts \\ [])

  def maybe_preload_pointers(object, keys, opts) when is_list(object) do
    debug("iterate list of objects")
    Enum.map(object, &maybe_preload_pointers(&1, keys, opts))
  end

  def maybe_preload_pointers(object, keys, opts)
      when is_list(keys) and length(keys) == 1 do
    # TODO: handle any size list and merge with accelerator?
    key = List.first(keys)
    debug(key, "list with one key")
    maybe_preload_pointers(object, key, opts)
  end

  def maybe_preload_pointers(object, key, opts)
      when is_struct(object) and is_map(object) and is_atom(key) do
    debug(key, "one field")

    case Map.get(object, key) do
      %Needle.Pointer{} = pointer ->
        Map.put(object, key, maybe_preload_pointer(pointer, opts))

      _ ->
        object
    end
  end

  def maybe_preload_pointers(object, {key, nested_keys}, opts)
      when is_struct(object) do
    debug(nested_keys, "key #{inspect(key)} with nested keys")

    object
    |> maybe_preload_pointer(opts)
    # |> IO.inspect
    |> Map.put(
      key,
      Map.get(object, key)
      |> maybe_preload_pointers(nested_keys, opts)
    )
  end

  def maybe_preload_pointers(object, keys, _opts) do
    debug(keys, "ignore #{inspect(keys)}")
    object
  end

  def maybe_preload_nested_pointers(object, keys, opts \\ [])

  def maybe_preload_nested_pointers(object, keys, opts)
      when is_list(keys) and length(keys) > 0 and is_map(object) do
    debug("maybe_preload_nested_pointers: try object with list of keys: #{inspect(keys)}")

    do_maybe_preload_nested_pointers(object, nested_keys(keys), opts)
  end

  def maybe_preload_nested_pointers(objects, keys, opts)
      when is_list(keys) and length(keys) > 0 and is_list(objects) and
             length(objects) > 0 do
    debug("maybe_preload_nested_pointers: try list with list of keys: #{inspect(keys)}")

    do_maybe_preload_nested_pointers(
      Enum.reject(objects, &(&1 == [])),
      [Access.all()] ++ nested_keys(keys),
      opts
    )
  end

  def maybe_preload_nested_pointers(object, _, _opts), do: object

  defp nested_keys(keys) do
    # keys |> Ecto.Repo.Preloader.normalize(nil, keys) |> IO.inspect
    # |> debug("flatten nested keys")
    keys |> Enums.flatter() |> Enum.map(&Access.key!(&1))
  end

  defp do_maybe_preload_nested_pointers(object, keylist, opts)
       when is_struct(object) or
              (is_list(object) and not is_nil(keylist) and keylist != []) do
    debug("do_maybe_preload_nested_pointers: try with get_and_update_in for #{inspect(object)}")

    # |> debug("object")
    with {_old, loaded} <-
           get_and_update_in(object, keylist, &{&1, maybe_preload_pointer(&1, opts)}) do
      loaded

      # |> debug("object")
    end
  end

  def maybe_preload_pointer(pointer, opts \\ [])

  def maybe_preload_pointer(%Needle.Pointer{} = pointer, opts) do
    debug("maybe_preload_pointer: follow")

    with {:ok, obj} <- Bonfire.Common.Needles.get(pointer, opts) do
      obj
    else
      e ->
        debug("maybe_preload_pointer: could not fetch pointer: #{inspect(e)} #{inspect(pointer)}")

        pointer
    end
  end

  # |> debug("skip")
  def maybe_preload_pointer(obj, _opts), do: obj
end
