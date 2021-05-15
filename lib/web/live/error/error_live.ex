defmodule Bonfire.Common.Web.ErrorLive do
  use Bonfire.Web, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
      |> assign_new(:page, fn -> nil end)
      |> assign_new(:current_account, fn -> nil end)
      |> assign_new(:current_user, fn -> nil end)
    }
  end

  defdelegate handle_params(params, attrs, socket), to: Bonfire.Web.LiveHandler
  def handle_event(action, attrs, socket), do: Bonfire.Web.LiveHandler.handle_event(action, attrs, socket, __MODULE__)
  def handle_info(info, socket), do: Bonfire.Web.LiveHandler.handle_info(info, socket, __MODULE__)

end
