defmodule Bonfire.Common.Pointers.Preload do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  require Logger

  def maybe_preload_pointers(keys, preloaded) when is_list(preloaded) do
    Logger.info("maybe_preload_pointers: iterate list of objects")
    Enum.map(preloaded, &maybe_preload_pointers(keys, &1))
  end

  # def maybe_preload_pointers(keys, preloaded) when is_list(keys) and length(keys)==1 do
  #   Logger.info("maybe_preload_pointers: just one")
  #   maybe_preload_pointers(List.first(keys), preloaded)
  # end

  # def maybe_preload_pointers(keys, preloaded) when is_list(keys) and is_map(preloaded) do
  #   Logger.info("maybe_preload_pointers: try with list of keys") # FIXME: optimise this based on keys that were preloaded
  #   for key <- keys, into: %{} do
  #     Logger.info("maybe_preload_pointers: try with #{inspect key}")
  #     {key,
  #       maybe_preload_pointer(Map.get(preloaded, key))
  #     )}
  #   end
  #   |> Map.merge(preloaded)
  # end

  # FIXME
  def maybe_preload_pointers(keys, preloaded) when is_list(keys) and length(keys)>0 and not is_nil(preloaded) do
    Logger.info("maybe_preload_pointers: try with list of keys: #{inspect keys}")

    # keys |> Ecto.Repo.Preloader.normalize(nil, keys) |> IO.inspect

    # keys |> Utils.maybe_to_map(true) |> IO.inspect

    keylist = keys |> Utils.flatter |> IO.inspect(label: "flatten keys") |> Enum.map(&Access.key!(&1))

    with {_old, loaded} <- preloaded
    |> get_and_update_in(keylist, &{&1, maybe_preload_pointer(&1)})
    do
      loaded
      # |> IO.inspect(label: "preloaded")
    end
  end

  def maybe_preload_pointers(key, preloaded) when is_map(preloaded) and is_atom(key) do
    Logger.info("maybe_preload_pointers: one field")
    case preloaded |> Map.get(key) do
      %Pointers.Pointer{} = pointer ->

        preloaded
        |> Map.put(key, Bonfire.Common.Pointers.follow!(pointer))

      _ -> preloaded
    end
  end

  def maybe_preload_pointers(_key, preloaded), do: preloaded

  def maybe_preload_pointer(%Pointers.Pointer{} = pointer) do
    Logger.info("maybe_preload_pointer: follow")

    Bonfire.Common.Pointers.follow!(pointer)
  end

  def maybe_preload_pointer(preloaded), do: preloaded #|> IO.inspect(label: "skip")

end
