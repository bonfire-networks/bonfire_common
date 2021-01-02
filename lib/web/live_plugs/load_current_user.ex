defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentUser do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Identity.{Accounts, Users}
  # alias Bonfire.Me.Web.SwitchUserLive
  alias Bonfire.Data.Identity.User

  # the non-live plug already supplied the current user
  def mount(_, _, %{assigns: %{current_user: %User{}}}=socket) do
    {:ok, socket}
  end

  def mount(_, %{"user_id" => id}, socket) do
    current_user = Users.get_current(id)
    # IO.inspect(current_user: current_user)
    check_user(current_user, socket)
  end

  # def mount(a, b, socket) do
  #   IO.inspect(a)
  #   IO.inspect(b)
  # end

  def mount(_, _, socket), do: check_user(nil, socket)

  defp check_user({:ok, user}, socket), do: check_user(user, socket)

  defp check_user(%User{} = user, socket) do
    {:ok, assign(socket, current_user: user)}
  end

  defp check_user(user, socket) do
    {:ok, socket}
    # Note: use UserRequired live plug instead if a user MUST be selected
    # path = Routes.switch_user_path(socket, :index)
    # {:halt, push_redirect(socket, to: path)}
  end

end
