defmodule Bonfire.Common.Pointers.Preload do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  require Logger

  def maybe_preload_pointers(object, keys) when is_list(object) do
    Logger.debug("maybe_preload_pointers: iterate list of objects")
    Enum.map(object, &maybe_preload_pointers(&1, keys))
  end

  def maybe_preload_pointers(object, keys) when is_list(keys) and length(keys)==1 do
    # TODO: handle any size list and merge with accelerator?
    key = List.first(keys)
    Logger.debug("maybe_preload_pointers: list with one key: #{inspect key}")
    maybe_preload_pointers(object, key)
  end

  def maybe_preload_pointers(object, key) when is_struct(object) and is_map(object) and is_atom(key) do
    Logger.debug("maybe_preload_pointers: one field: #{inspect key}")
    case Map.get(object, key) do
      %Pointers.Pointer{} = pointer ->

        object
        |> Map.put(key, maybe_preload_pointer(pointer))

      _ -> object
    end
  end

  def maybe_preload_pointers(object, {key, nested_keys}) when is_struct(object) do

    Logger.debug("maybe_preload_pointers: key #{key} with nested keys #{inspect nested_keys}")
    object
    |> maybe_preload_pointer()
    # |> IO.inspect
    |> Map.put(key,
      Map.get(object, key)
      |> maybe_preload_pointers(nested_keys)
    )
  end

  def maybe_preload_pointers(object, keys) do
    Logger.debug("maybe_preload_pointers: ignore #{inspect keys}")
    object
  end


  def maybe_preload_nested_pointers(object, keys, opts \\ [])

    def maybe_preload_nested_pointers(object, keys, opts) when is_list(keys) and length(keys)>0 and is_map(object) do
    Logger.debug("maybe_preload_nested_pointers: try object with list of keys: #{inspect keys}")

    do_maybe_preload_nested_pointers(object, nested_keys(keys), opts)
  end

  def maybe_preload_nested_pointers(object, keys, opts) when is_list(keys) and length(keys)>0 and is_list(object) and length(object)>0 do
    Logger.debug("maybe_preload_nested_pointers: try list with list of keys: #{inspect keys}")

    do_maybe_preload_nested_pointers(
      object |> Enum.reject(&(&1==[])),
      [Access.all()] ++ nested_keys(keys),
      opts
    )
  end

  def maybe_preload_nested_pointers(object, _, _opts), do: object

  defp nested_keys(keys) do
    # keys |> Ecto.Repo.Preloader.normalize(nil, keys) |> IO.inspect
    keys |> Utils.flatter |> Enum.map(&Access.key!(&1)) # |> IO.inspect(label: "flatten nested keys")
  end

  defp do_maybe_preload_nested_pointers(object, keylist, opts) when keylist !=[] do
    Logger.debug("do_maybe_preload_nested_pointers: try with get_and_update_in")

    with {_old, loaded} <- object
                          # |> IO.inspect(label: "object")
                          |> get_and_update_in(keylist, &{&1, maybe_preload_pointer(&1, opts)})
    do
      loaded
      # |> IO.inspect(label: "object")
    end
  end


  def maybe_preload_pointer(%Pointers.Pointer{} = pointer, opts \\ []) do
    Logger.debug("maybe_preload_pointer: follow")

    with {:ok, obj} <- Bonfire.Common.Pointers.get(pointer, opts) do
      obj
    else e ->
      Logger.debug("maybe_preload_pointer: could not fetch pointer: #{inspect e} #{inspect pointer}")
      pointer
    end
  end

  def maybe_preload_pointer(obj, _opts), do: obj #|> IO.inspect(label: "skip")


end
