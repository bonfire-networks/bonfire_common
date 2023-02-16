defmodule Bonfire.Common.Presence do
  use Phoenix.Presence,
    otp_app: :bonfire,
    pubsub_server: Bonfire.Common.PubSub

  import Untangle
  alias Bonfire.Common.Utils

  @presence "bonfire:presence"

  @doc "Join a user to the list of those who are present"
  def present!(socket, meta \\ %{}) do
    if Utils.socket_connected?(socket) do
      user_id = Utils.current_user_id(socket)

      if user_id do
        {:ok, _} =
          track(
            self(),
            @presence,
            user_id,
            Enum.into(meta, %{
              # name: user_id[:name],
              pid: self(),
              joined_at: :os.system_time(:seconds)
            })
          )

        debug(user_id, "joined")
      else
        debug("skip because we have no user")
      end
    else
      debug("skip because socket not connected")
    end

    socket
  end

  @doc "Check if a given user (or the current user) is in the list of those who are present"
  def present?(user_id \\ nil, socket) do
    present_meta(user_id, socket)
  end

  def present_meta(user \\ nil, socket) do
    user_id =
      (Utils.current_user_id(user) || Utils.current_user_id(socket))
      |> debug("user_id")

    if user_id do
      get_by_key(
        @presence,
        user_id
      )
      |> Utils.e(:metas, [])
      |> debug()
    end
  end

  def list() do
    list(@presence)
  end

  def list_and_maybe_subscribe_to_presence(socket) do
    if Utils.socket_connected?(socket) do
      Phoenix.PubSub.subscribe(PubSub, @presence)
    end

    socket
    |> Phoenix.Component.assign(:users, %{})
    |> handle_joins(list())
  end

  # act joins/leave if subscribed to them
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    {
      :noreply,
      socket
      |> handle_leaves(diff.leaves)
      |> handle_joins(diff.joins)
    }
  end

  defp handle_joins(socket, joins) do
    Enum.reduce(joins, socket, fn {user, %{metas: [meta | _]}}, socket ->
      Phoenix.Component.assign(socket, :users, Map.put(socket.assigns.users, user, meta))
    end)
  end

  defp handle_leaves(socket, leaves) do
    Enum.reduce(leaves, socket, fn {user, _}, socket ->
      Phoenix.Component.assign(socket, :users, Map.delete(socket.assigns.users, user))
    end)
  end
end
