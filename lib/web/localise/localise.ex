defmodule Bonfire.Web.Localise do
  @moduledoc """
  Various helpers for localisation
  """

  def default_locale, do: Bonfire.Common.Config.get(:default_locale, "en")

  def known_locales, do: [default_locale] ++ Gettext.known_locales(Bonfire.Web.Gettext)

  def put_locale(locale) do
    Bonfire.Web.Cldr.put_locale(locale)
    Gettext.put_locale(Bonfire.Web.Gettext, locale)
  end

  def locale_name(locale) do
    # FIXME, not sure why the Cldr.Language provider is not being compiled in
    with {:ok, name} <- Bonfire.Common.Utils.maybe_apply(Bonfire.Web.Cldr.Backend.Language, :to_string, locale) do
      name
    else _ ->
        locale
    end
  end
end
