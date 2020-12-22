defmodule Bonfire.Common.Web.LivePlugs.AccountRequired do

  use Bonfire.Web, :live_plug
  alias Bonfire.Data.Identity.Account

  def mount(_params, _session, socket), do: check(socket.assigns[:current_account], socket)

  defp check(%Account{}, socket), do: {:ok, socket}
  defp check(_, socket) do
    {:halt,
     socket
     |> put_flash(:error, "You must log in to view that page.")
     |> go(Routes.login_path(socket, :index))}
  end

  # TODO: should we preserve query strings?
  defp go(conn, path) do
    path = path <> "?" <> Query.encode(go: conn.requested_path)
    redirect(conn, to: path)
  end

end
