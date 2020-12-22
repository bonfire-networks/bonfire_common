defmodule Bonfire.Common.Web.LivePlugs.UserRequired do

  use Bonfire.Web, :live_plug
  alias Bonfire.Data.Identity.{Account, User}
  alias Plug.Conn.Query

  def mount(_params, _session, %{assigns: the}=socket) do
    check(the[:current_user], the[:current_account], socket)
  end

  defp check(%User{}, _account, socket), do: {:ok, socket}

  defp check(_user, %Account{}, socket) do
    {:halt,
     socket
     |> put_flash(:info, "You must choose a user to see that page.")
     |> go(Routes.switch_user_path(socket, :index))}
  end

  defp check(_user, _account, socket) do
    {:halt,
     socket
     |> put_flash(:info, "You must log in to see that page.")
     |> go(Routes.login_path(socket, :index))}
  end

  # TODO: should we preserve query strings?
  defp go(socket, path) do
    path = path <> "?" <> Query.encode(go: socket.requested_path)
    push_redirect(socket, to: path)
  end

end
