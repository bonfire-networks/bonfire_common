defmodule Bonfire.Common.Localise do
  @moduledoc """
  Various helpers for localisation
  """
  alias Bonfire.Common.Utils

  defmacro __using__(_opts) do
    quote do
      require Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  def default_locale, do: Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :default_locale], "en")

  def known_locales do
    Bonfire.Common.Localise.Cldr.known_locale_names()
    # ([default_locale()]
    # ++ Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :locales], [])
    # ++ Gettext.known_locales(Bonfire.Common.Localise.Gettext))
    # |> Enum.uniq()
  end

  def get_locale() do
    # Cldr locale
    Bonfire.Common.Localise.Cldr.get_locale()

    # Gettext locale
    # Gettext.get_locale(Bonfire.Common.Localise.Gettext)
  end

  def get_locale_id() do
    locale = get_locale()
    Utils.e(locale, :cldr_locale_name, locale)
  end

  def put_locale(locale) do
    # change Cldr locale
    Bonfire.Common.Localise.Cldr.put_locale(locale)

    # Sets the global Gettext locale for the current process.
    Gettext.put_locale(to_string(locale))

    # change Gettext locale
    # Gettext.put_locale(Bonfire.Common.Localise.Gettext, to_string(locale))

    # change Gettext locale of extra deps
    # Enum.each(Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :extra_gettext], []), & Gettext.put_locale(&1, to_string(locale)) )
  end

  def locale_name(locale) when is_atom(locale), do: Atom.to_string(locale) |> locale_name()
  def locale_name(locale) do
    # FIXME, not sure why the Cldr.Language provider is not being compiled in
    with {:ok, name} <- Utils.maybe_apply(Bonfire.Common.Localise.Cldr.Language, :to_string, locale) do
      name
    else _ ->
        locale
    end
  end

  def set_locale_config() do
    [
      default: Bonfire.Common.Localise.default_locale(),
	    apps: [gettext: :global, cldr: :global],
	    from: [:session, :cookie, :accept_language, :query],
	    gettext: Bonfire.Common.Localise.Gettext,
	    cldr: Bonfire.Common.Localise.Cldr
    ]
  end
end
