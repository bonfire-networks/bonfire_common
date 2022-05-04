defmodule Bonfire.Common.Localise do
  @moduledoc """
  Various helpers for localisation
  """

  defmacro __using__(_opts) do
    quote do
      require Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  def default_locale, do: Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :default_locale], "en")

  def known_locales, do: ([default_locale()] ++ Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :locales], []) ++ Gettext.known_locales(Bonfire.Common.Localise.Gettext)) |> Enum.uniq()

  def put_locale(locale) do
    Bonfire.Common.Localise.Cldr.put_locale(locale)
    Gettext.put_locale(Bonfire.Common.Localise.Gettext, to_string(locale))
  end

  def locale_name(locale) do
    # FIXME, not sure why the Cldr.Language provider is not being compiled in
    with {:ok, name} <- Bonfire.Common.Utils.maybe_apply(Bonfire.Common.Localise.Cldr.Backend.Language, :to_string, locale) do
      name
    else _ ->
        locale
    end
  end
end
