defmodule Bonfire.Notifications.LiveHandler do
  use Bonfire.Web, :live_handler

  def handle_event("request", attrs, socket) do
    Bonfire.Notifications.do_notify(%{tile: "Receive notifications?", message: "OK"}, socket)
  end

  def handle_info(attrs, socket) do
    Bonfire.Notifications.do_notify(attrs, socket)
  end

end
