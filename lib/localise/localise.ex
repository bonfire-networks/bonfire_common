defmodule Bonfire.Common.Localise do
  @moduledoc """
  Various helpers for localisation
  """
  use Bonfire.Common.E
  use Bonfire.Common.Config
  import Untangle
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Types
  alias Bonfire.Common.Cache

  defmacro __using__(_opts) do
    quote do
      use Gettext, backend: Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  @doc """
  Registers the object type names for gettext extraction, at compile time.

  Object type names ("post", "user", "article") are derived from the loaded schema modules rather than written out in source, so `mix gettext.extract` cannot find them by walking `l/1` call sites — they have to be enumerated and handed to `localise_strings/3` explicitly. They are looked up at runtime by `Bonfire.Common.Types.object_type_display/1`.

  ## Where to call this from

  **A flavour extension, not the root app.** Under `AS_UMBRELLA=1` — which `just localise-extract` requires, so that extraction can see extension sources at all — `apps_path` makes the root project an umbrella *container*, and umbrella roots do not own source. Anything in the root's `lib/` is therefore never compiled during extraction, its macros never expand, and it contributes nothing. (This is why `bonfire.po` sat empty and only a handful of hand-added object types ever existed.)

  A flavour extension is the right home because it is by definition the thing that depends on every extension in its build, so all sibling apps are loaded by the time it compiles — which is what `Bonfire.Common.Types.all_object_type_names/0` needs, since it enumerates via `Application.loaded_applications/0`.

      defmodule Social.Localise do
        use Bonfire.Common.Localise
        Bonfire.Common.Localise.localise_object_type_names()
      end

  ## Why only object types

  Every other runtime-derived set belongs to the extension that declares it, and is emitted there — activity verbs by `bonfire_social`, base verb forms by `bonfire_boundaries` via plain `l/4` (they stay context-less, being the base sense). Only object types span every extension at once, so only they need a vantage point that can see them all. Emitting another extension's strings from here would also put them in the wrong gettext domain.
  """
  defmacro localise_object_type_names do
    quote do
      Bonfire.Common.Types.all_object_type_names()
      |> Bonfire.Common.Localise.Gettext.Helpers.localise_strings(
        Bonfire.Common.Types,
        "object"
      )
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
  Gets the known locales from both Cldr and Gettext.

  ## Examples

      > known_locales()
      [:en, :es, :fr]

  """
  def known_locales do
    # Add default locale to ensure it's always included
    default =
      default_locale()
      |> normalize_locale()

    cldr_locales = Bonfire.Common.Localise.Cldr.known_locale_names()
    # |> Enum.map(&normalize_locale/1)

    # Only include configured locales if specified
    # config_locales = Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :locales], [])

    gettext_locales =
      gettext_localisation_locales()
      |> Enum.map(&normalize_locale/1)

    ([default] ++ cldr_locales ++ gettext_locales)
    |> Enum.uniq()
  end

  def localisation_locales do
    # Add default locale to ensure it's always included
    default = default_locale()

    ([default] ++ gettext_localisation_locales())
    |> Enum.map(&normalize_locale/1)
    |> Enum.uniq()
  end

  defp gettext_localisation_locales do
    Gettext.known_locales(Bonfire.Common.Localise.Gettext)
  end

  defp normalize_locale(locale) when is_binary(locale) do
    locale
    |> String.replace("_", "-")
    |> Types.maybe_to_atom()
  end

  defp normalize_locale(locale) when is_atom(locale) do
    locale
    # |> Atom.to_string()
    # |> String.replace("_", "-")
    # |> Types.maybe_to_atom()
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
    e(locale, :cldr_locale_name, nil) || locale
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

    # Resolve the correct Gettext locale name from the CLDR locale tag.
    # CLDR uses BCP47 format (e.g. "zh-TW") while Gettext uses POSIX format (e.g. "zh_TW").
    # Without this mapping, locales like zh-Hant/zh-TW won't find their Gettext translations.
    gettext_locale =
      case Bonfire.Common.Localise.Cldr.validate_locale(locale) do
        {:ok, %{gettext_locale_name: name}} when not is_nil(name) ->
          to_string(name)

        _ ->
          to_string(locale)
      end

    # Sets the global Gettext locale for the current process.
    Gettext.put_locale(gettext_locale)

    # change Gettext locale
    # Gettext.put_locale(Bonfire.Common.Localise.Gettext, to_string(locale))

    # change Gettext locale of extra deps
    # Enum.each(Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :extra_gettext], []), & Gettext.put_locale(&1, to_string(locale)) )
  end

  defp valid_locale?(locale) do
    case Bonfire.Common.Localise.Cldr.validate_locale(locale) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def put_best_locale_match(
        desired,
        default \\ default_locale(),
        supported \\ localisation_locales()
      )
      when is_list(desired) do
    filtered =
      desired
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&Bonfire.Common.Localise.Cldr.validate_locale(&1))
      |> Enum.filter_map(
        fn
          {:ok, tag} -> true
          _ -> false
        end,
        fn {:ok, tag} -> tag end
      )

    if filtered == [] do
      error_or_set_default_locale("No valid preferred locales", default)
    else
      case Cldr.Locale.Match.best_match(filtered, supported: supported) do
        {:ok, best, _score} ->
          put_locale(best)
          {:ok, best}

        e ->
          error_or_set_default_locale(e, default)
      end
    end
  end

  defp error_or_set_default_locale(e, default) do
    if default do
      warn(e, "No locale match found from preferred locales, setting a default")
      put_locale(default)
      {:ok, default}
    else
      error(e)
    end
  end

  @doc """
  Converts a locale atom to its string representation.

  ## Examples

      iex> locale_name(:en)
      "English"
      iex> locale_name("fr")
      "français"

  """
  def locale_name(locale) when is_atom(locale),
    do: Atom.to_string(locale) |> locale_name()

  def locale_name(locale) do
    with {:ok, lang_localized} <- Cldr.LocaleDisplay.display_name(locale, locale: locale) do
      lang_localized
    else
      _ ->
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
  end

  @doc "Returns a list of locales paired with their localised display names, sorted alphabetically by display name."
  def locales_with_names(locales) do
    # Cached: building this list calls the expensive `locale_name/1` (CLDR display-name lookup +
    # reflection fallback) once per locale, and the language selectors re-evaluate it on every render
    # for all (~120 in prod) installed locales. The result only changes when the set of installed
    # locales does (i.e. on deploy), so memoise it keyed on the given `locales`.
    Cache.maybe_apply_cached(&do_locales_with_names/1, [locales])
  end

  defp do_locales_with_names(locales) do
    locales
    |> Enum.map(fn l -> {l, locale_name(l)} end)
    |> Enum.sort_by(&elem(&1, 1))
  end

  @doc "Returns known locales paired with their localised display names, sorted alphabetically by display name."
  def known_locales_names_localised do
    localisation_locales()
    |> locales_with_names()
  end

  @doc "Config for the `Cldr.Plug.SetLocale` plug"
  def set_locale_config() do
    [
      default: Bonfire.Common.Localise.Cldr.default_locale(),
      apps: [gettext: :global, cldr: :global],
      from: [:session, :cookie, :query, :accept_language],
      param: "locale",
      gettext: Bonfire.Common.Localise.Gettext,
      cldr: Bonfire.Common.Localise.Cldr
    ]
  end
end
