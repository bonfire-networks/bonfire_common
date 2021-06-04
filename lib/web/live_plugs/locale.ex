defmodule Bonfire.Web.LivePlugs.Locale do

  import Phoenix.LiveView

  def mount(_, %{"locale" => locale}, socket), do: put_locale(locale, socket)
  def mount(_, _, socket), do: put_locale(Bonfire.Web.Gettext.default_locale, socket)

  def put_locale(locale, socket) do
    Gettext.put_locale(Bonfire.Web.Gettext, locale)

    {:ok, assign(socket, :locale, locale)}
  end

end
