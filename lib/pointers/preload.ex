defmodule Bonfire.Common.Pointers.Preload do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  require Logger

  def maybe_preload_pointers(preloaded, keys) when is_list(preloaded) do
    Logger.info("maybe_preload_pointers: iterate list of objects")
    Enum.map(preloaded, &maybe_preload_pointers(&1, keys))
  end

  def maybe_preload_pointers(preloaded, keys) when is_list(keys) and length(keys)==1 do
    Logger.info("maybe_preload_pointers: list with one key")
    maybe_preload_pointers(preloaded, List.first(keys))
  end

  def maybe_preload_pointers(preloaded, key) when is_map(preloaded) and is_atom(key) do
    Logger.info("maybe_preload_pointers: one field")
    case Map.get(preloaded, key) do
      %Pointers.Pointer{} = pointer ->

        preloaded
        |> Map.put(key, maybe_preload_pointer(pointer))

      _ -> preloaded
    end
  end

  def maybe_preload_pointers(preloaded, _keys), do: preloaded


  def maybe_preload_nested_pointers(preloaded, keys) when is_list(keys) and length(keys)>0 and is_map(preloaded) do
    Logger.info("maybe_preload_nested_pointers: try object with list of keys: #{inspect keys}")

    do_maybe_preload_nested_pointers(preloaded, nested_keys(keys))
  end

  def maybe_preload_nested_pointers(preloaded, keys) when is_list(keys) and length(keys)>0 and is_list(preloaded) do
    Logger.info("maybe_preload_nested_pointers: try list with list of keys: #{inspect keys}")

    do_maybe_preload_nested_pointers(preloaded, [Access.all()] ++ nested_keys(keys))
  end

  def maybe_preload_nested_pointers(preloaded, _), do: preloaded

  defp nested_keys(keys) do
    # keys |> Ecto.Repo.Preloader.normalize(nil, keys) |> IO.inspect
    keys |> Utils.flatter |> IO.inspect(label: "flatten keys") |> Enum.map(&Access.key!(&1))
  end

  defp do_maybe_preload_nested_pointers(preloaded, keylist) do

    with {_old, loaded} <- preloaded
    |> get_and_update_in(keylist, &{&1, maybe_preload_pointer(&1)})
    do
      loaded
      # |> IO.inspect(label: "preloaded")
    end
  end


  def maybe_preload_pointer(%Pointers.Pointer{} = pointer) do
    Logger.info("maybe_preload_pointer: follow")

    Bonfire.Common.Pointers.get!(pointer)
  end

  def maybe_preload_pointer(obj), do: obj #|> IO.inspect(label: "skip")


end
