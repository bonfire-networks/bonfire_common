defmodule Bonfire.Common.Web.LivePlugs.AdminRequired do

  use Bonfire.Web, :live_plug
  alias Bonfire.Data.Identity.Account

  def mount(_params, _session, socket), do: check(socket.assigns[:current_account], socket)

  defp check(%Account{instance_admin: %{is_instance_admin: true}}, socket), do: {:ok, socket}
  defp check(_, socket) do
    {:halt,
     socket
     |> put_flash(:error, "That page is only accessible to instance administrators.")
     |> push_redirect(to: Routes.login_path(socket))}
  end

end
