defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentAccountFromSession do

  import Phoenix.LiveView
  alias Bonfire.Me.{Accounts, Users}

  def mount(_params, session, socket) do
    {:ok, mount(session, assign(socket, current_user: nil, current_account: nil))}
  end

  def mount(%{"account_id" => id}, socket) when is_binary(id) do
    assign(socket, current_account: Accounts.get_for_session(id))
  end

  def mount(_, socket), do: socket

end
