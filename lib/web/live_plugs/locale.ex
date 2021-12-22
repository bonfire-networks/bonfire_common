defmodule Bonfire.Web.LivePlugs.Locale do

  import Phoenix.LiveView

  @local_session_key Cldr.Plug.SetLocale.session_key()

  def mount(_, %{"locale" => locale}, socket), do: do_put_locale(locale, socket)
  def mount(_, %{@local_session_key => locale}, socket), do: do_put_locale(locale, socket)
  def mount(_, _, socket), do: do_put_locale(Bonfire.Web.Localise.default_locale, socket)

  defp do_put_locale(locale, socket) do
    Bonfire.Web.Localise.put_locale(locale)

    {:ok, assign(socket, :locale, locale)}
  end

end
