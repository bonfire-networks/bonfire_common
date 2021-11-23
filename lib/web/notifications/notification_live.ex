defmodule Bonfire.Common.Web.NotificationLive do
  use Bonfire.Web, :stateful_component
  alias Bonfire.Web.LivePlugs
  require Logger

  prop notification, :any

  def mount(socket) do
    inbox_id = Bonfire.Social.Feeds.my_inbox_feed_id(socket)
    if inbox_id do
        pubsub_subscribe(inbox_id, socket)
    else
      Logger.info("not subscribing to notifications")
    end

    {:ok, socket}
  end
  # defdelegate handle_params(params, attrs, socket), to: Bonfire.Common.LiveHandlers
  # def handle_event(action, attrs, socket), do: Bonfire.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)
  # def handle_info(info, socket), do: Bonfire.Common.LiveHandlers.handle_info(info, socket, __MODULE__)

end
