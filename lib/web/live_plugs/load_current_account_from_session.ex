defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentAccount do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Identity.Accounts
  alias Bonfire.Data.Identity.Account

  # the non-live plug already supplied the current account
  def mount(_, _, %{assigns: %{current_account: %Account{}}}=socket), do: {:ok, socket} #|> IO.inspect
  def mount(_, %{"account_id" => id}, socket), do: check_account(Accounts.get_current(id), socket) #|> IO.inspect
  def mount(_, _, socket), do: check_account(nil, socket)

  defp check_account(%Account{}=account, socket),
    do: {:ok, assign(socket, current_account: account)}

  defp check_account(_, socket) do
    {:halt,
     socket
     |> push_redirect(to: Routes.login_path(socket, :index))}
  end

end
