defmodule Bonfire.Common.Web.ComponentID do

  def new(component_module, object_id) when is_binary(object_id) do
    component_id = Pointers.ULID.generate()

    save(component_module, object_id, component_id)

    component_id
  end

  def send_updates(component_module, object_id, assigns) do
    for component_id <- ids(component_module, object_id) do
      Phoenix.LiveView.send_update(component_module, [id: component_id] ++ assigns)
    end
  end


  def ids(component_module, object_id), do: dictionary_key_id(component_module, object_id) |> ids()

  defp ids(dictionary_key_id) when is_binary(dictionary_key_id) do
    Process.get(dictionary_key_id, [])
  end


  defp dictionary_key_id(component_module, object_id), do: "cid_"<>to_string(component_module)<>"_"<>object_id |> IO.inspect()


  defp save(component_module, object_id, component_id) when is_binary(object_id) and is_binary(component_id) do
    dictionary_key_id = dictionary_key_id(component_module, object_id)

    Process.put(dictionary_key_id,
      (ids(dictionary_key_id) ++ [component_id])
      |> IO.inspect()
    )
  end

end
