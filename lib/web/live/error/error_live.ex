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

end
