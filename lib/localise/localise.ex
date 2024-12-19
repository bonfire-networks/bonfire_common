defmodule Bonfire.Common.Localise do
  @moduledoc """
  Various helpers for localisation
  """
  use Bonfire.Common.E
  alias Bonfire.Common.Utils

  defmacro __using__(_opts) do
    quote do
      use Gettext, backend: Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  @doc """
  Gets the default locale from the configuration or returns "en".

  ## Examples

      iex> default_locale()
      "en"

  """
  def default_locale,
    do:
      Bonfire.Common.Config.get(
        [Bonfire.Common.Localise.Cldr, :default_locale],
        "en"
      )

  @doc """
  Gets the known locales from the Cldr module.

  ## Examples

      > known_locales()
      [:en, :es, :fr]

  """
  def known_locales do
    Bonfire.Common.Localise.Cldr.known_locale_names()
    # ([default_locale()]
    # ++ Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :locales], [])
    # ++ Gettext.known_locales(Bonfire.Common.Localise.Gettext))
    # |> Enum.uniq()
  end

  @doc """
  Gets the current locale from the Cldr module.

  ## Examples

      iex> get_locale()
      Bonfire.Common.Localise.Cldr.Locale.new!("en")
  """
  def get_locale() do
    # Cldr locale
    Bonfire.Common.Localise.Cldr.get_locale()

    # Gettext locale
    # Gettext.get_locale(Bonfire.Common.Localise.Gettext)
  end

  @doc """
  Gets the current locale ID.

  ## Examples

      iex> get_locale_id()
      :en

  """
  def get_locale_id() do
    locale = get_locale()
    e(locale, :cldr_locale_name, locale)
  end

  @doc """
  Sets the given locale for both Cldr and Gettext.

  ## Examples

      iex> put_locale("es")
      nil

  """
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

  @doc """
  Converts a locale atom to its string representation.

  ## Examples

      iex> locale_name(:en)
      "English"
      iex> locale_name("fr")
      "French"

  """
  def locale_name(locale) when is_atom(locale),
    do: Atom.to_string(locale) |> locale_name()

  def locale_name(locale) do
    # FIXME, not sure why the Cldr.Language provider is not being compiled in
    with {:ok, name} <-
           Utils.maybe_apply(
             Bonfire.Common.Localise.Cldr.Language,
             :to_string,
             locale
           ) do
      name
    else
      _ ->
        locale
    end
  end

  @doc "Config for the `Cldr.Plug.SetLocale` plug"
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
