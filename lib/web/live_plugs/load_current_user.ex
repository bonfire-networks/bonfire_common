defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentUser do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Identity.{Accounts, Users}
  alias Bonfire.Me.Web.SwitchUserLive
  alias Bonfire.Data.Identity.User

  # the non-live plug already supplied the current user
  def mount(_, _, %{assigns: %{current_user: %User{}}}=socket) do
    {:ok, socket}
  end

  def mount(_, %{"user_id" => id}, socket) do
    check_user(Users.get_current(id), socket)
  end

  def mount(_, _, socket), do: check_user(nil, socket)

  defp check_user({:ok, user}, socket) do
    {:ok, assign(socket, current_user: user)}
  end

  defp check_user(_, socket) do
    path = Routes.live_path(socket, SwitchUserLive)
    {:halt, push_redirect(socket, to: path)}
  end

end
