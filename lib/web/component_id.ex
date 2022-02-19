defmodule Bonfire.Common.Web.ComponentID do
  import Where
  alias Bonfire.Common.Utils

  def new(component_module, object_id) when is_binary(object_id) do
    component_id = Pointers.ULID.generate()
    debug("ComponentID: stateless component #{component_module} for object id #{object_id} now has ID: #{component_id}")

    save(component_module, object_id, component_id)

    component_id
  end
  def new(component_module, %{id: object_id}) do
    new(component_module, object_id)
  end
  def new(component_module, _) do
    error("ComponentID: not object ID known for #{component_module}")
    Pointers.ULID.generate()
  end


  def send_updates(component_module, object_id, assigns) do
    debug("ComponentID: try to send_updates to #{component_module} for object id #{object_id}")

    for component_id <- ids(component_module, object_id) do
      debug("ComponentID: try stateful component with ID #{component_id}")
      Phoenix.LiveView.send_update(component_module, [id: component_id] ++ assigns)
    end
  end

  def send_assigns(component_module, id, set, socket) do

    Utils.maybe_str_to_atom(component_module)
    |>
    send_updates(id, set)

    # {:noreply, Phoenix.LiveView.assign(socket, set)}
    {:noreply, socket}
  end


  def ids(component_module, object_id), do: dictionary_key_id(component_module, object_id) |> ids()

  defp ids(dictionary_key_id) when is_binary(dictionary_key_id) do
    Process.get(dictionary_key_id, [])
  end


  defp dictionary_key_id(component_module, object_id), do: "cid_"<>to_string(component_module)<>"_"<>object_id #|> debug()


  defp save(component_module, object_id, component_id) when is_binary(object_id) and is_binary(component_id) do
    dictionary_key_id = dictionary_key_id(component_module, object_id)

    Process.put(dictionary_key_id,
      (ids(dictionary_key_id) ++ [component_id])
      #|> debug()
    )
  end

end
