defmodule Bonfire.Common.Web.NotificationLive do
  use Bonfire.Web, :stateful_component
  alias Bonfire.Web.LivePlugs
  require Logger

  prop notification, :any

  def mount(socket) do
    feed_id = Bonfire.Social.Feeds.my_feed_id(:notifications, socket)
    if feed_id do
        pubsub_subscribe(feed_id, socket)
    else
      Logger.info("NotificationLive: no feed_id so not subscribing to push notifications")
    end

    {:ok, socket}
  end
  # defdelegate handle_params(params, attrs, socket), to: Bonfire.Common.LiveHandlers
  # def handle_event(action, attrs, socket), do: Bonfire.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)
  # def handle_info(info, socket), do: Bonfire.Common.LiveHandlers.handle_info(info, socket, __MODULE__)

end
