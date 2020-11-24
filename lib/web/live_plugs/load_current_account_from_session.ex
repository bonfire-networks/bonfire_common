defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentAccountFromSession do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Accounts
  alias CommonsPub.Accounts.Account

  # the non-live plug already supplied the current account
  def mount(_, _, %{assigns: %{current_account: %Account{}}}=socket), do: {:ok, socket}
  def mount(_, %{"account_id" => id}, socket), do: check_account(Accounts.get_current(id), socket)
  def mount(_, _, socket), do: check_account(nil, socket)

  defp check_account({:ok, account}, socket), do: {:ok, assign(socket, current_account: account)}
  defp check_account(_, socket), do: {:halt, push_redirect(socket, to: Routes.login_path(socket, :index))}

end
