defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentAccountUsers do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Identity.Users
  alias Bonfire.Data.Identity.Account

  def mount(_, _, %{assigns: %{current_account: %Account{}=account}}=socket) do
    {:ok, assign(socket, current_account_users: Users.by_account(account))}
  end

  def mount(_, _, socket), do: {:ok, socket}

end
