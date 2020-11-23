defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentUserFromPath do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.{Accounts, Users}
  alias Bonfire.Me.Web.{SwitchUserLive}

  def mount(%{"as_username" => username}, _session, socket) do
    case Users.get_current(username, socket.assigns[:current_account]) do
      {:ok, user} -> {:ok, assign(socket, current_user: user)}
      _ -> no(socket)
    end
  end
  def mount(_, _, socket), do: no(socket)

  def no(socket),
    do: {:halt, push_redirect(socket, to: Routes.live_path(socket, SwitchUserLive))}

end
