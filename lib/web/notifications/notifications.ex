defmodule Bonfire.Notifications do
  use Bonfire.Web, :live_handler

  def notify_users(feed_ids, title, message) do
    pubsub_broadcast(feed_ids, {Bonfire.Notifications, %{title: title, message: text_only(message)}})
  end

  def notify(title, message, socket \\ nil) do
    do_notify(
      %{title: title, message: message}
      |> debug(),
    socket)
  end


  def do_notify(attrs, socket \\ nil)

  def do_notify(attrs, nil) do
    send_update(Bonfire.Common.Web.NotificationLive, Map.merge(%{id: "notification"}, attrs))
  end

  def do_notify(attrs, socket) do
    {:noreply,
      socket
      |> assign(notification: attrs)
      |> push_event("notify", attrs)
    }
  end

  # def process_state(pid) when is_pid(pid), do: :sys.get_state(pid)


end
