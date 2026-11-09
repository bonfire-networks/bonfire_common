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
  alias Bonfire.Common.Localise.Gettext.Fallback

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
    # one call per owner, since `localise_strings/3` takes a single module and so a single domain
    for {owner, names} <- Bonfire.Common.Types.all_object_type_names_by_owner() do
      quote do
        Bonfire.Common.Localise.Gettext.Helpers.localise_strings(
          unquote(names),
          unquote(owner),
          "object"
        )
      end
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
      requested_gettext_locale(locale) ||
        case Bonfire.Common.Localise.Cldr.validate_locale(locale) do
          {:ok, %{gettext_locale_name: name}} when not is_nil(name) ->
            to_string(name)

          _ ->
            to_string(locale)
        end

    # Sets the global Gettext locale for the current process.
    Gettext.put_locale(gettext_locale)

    # the extra languages belong to the previous locale choice, so a caller that wants them stores them again with `put_fallback_extras/1`
    Fallback.delete_extras()

    # change Gettext locale
    # Gettext.put_locale(Bonfire.Common.Localise.Gettext, to_string(locale))

    # change Gettext locale of extra deps
    # Enum.each(Bonfire.Common.Config.get([Bonfire.Common.Localise.Cldr, :extra_gettext], []), & Gettext.put_locale(&1, to_string(locale)) )
  end

  @doc """
  Returns the requested locale as a Gettext locale name (eg. `"fr_FR"` for `"fr-FR"`) if a catalogue with exactly that name exists, otherwise `nil`.

  ex_cldr resolves `fr-FR` to `fr` for Gettext because both score the same and `fr` sorts first, so the user's regional choice would otherwise never reach the regional catalogue.
  """
  def requested_gettext_locale(%{requested_locale_name: name}) when not is_nil(name),
    do: requested_gettext_locale(name)

  def requested_gettext_locale(locale) when is_binary(locale) or is_atom(locale) do
    name = locale |> to_string() |> String.replace("-", "_")

    if name in Gettext.known_locales(Bonfire.Common.Localise.Gettext), do: name
  end

  def requested_gettext_locale(_), do: nil

  @doc """
  Switches the Gettext locale to the first of the `desired` locales that has a catalogue of exactly that name, as long as it is in the same language as the `chosen` locale (the one already set from the best match), so the CLDR locale and the language picked stay as ex_cldr resolved them.
  """
  def put_requested_gettext_locale(desired, chosen) do
    language = locale_language(chosen)

    found =
      Enum.find_value(List.wrap(desired), fn d ->
        with name when is_binary(name) <- requested_gettext_locale(d),
             true <- locale_language(name) == language do
          name
        else
          _ -> nil
        end
      end)

    if found, do: Gettext.put_locale(found)
    found
  end

  @doc "How many extra languages (see `put_fallback_extras/1`) a single missing string is tried in, counting only those that have a catalogue for its domain."
  def max_fallback_extras, do: Bonfire.Common.Config.get([__MODULE__, :max_fallback_extras], 3)

  @doc "The session key under which the `set_locale` plug keeps the browser's extra languages, for the LiveView on_mount to read."
  def fallback_session_key, do: "fallback_locales"

  @doc """
  Stores, in the current process, the languages to try for a string that the current Gettext locale (and its base language) has not translated: the user's "Other languages I understand", the browser's `Accept-Language` extras and the instance's, in that order. `Bonfire.Common.Localise.Gettext` reads them on a miss.

  Call it after the Gettext locale is set (`put_locale/1` clears them). An extra is dropped if ex_cldr does not know it, or if it has no Gettext catalogue at all, neither of its own nor for its base language (`de_CH` is kept for `de`). Then the list is deduped, left out where it repeats the current locale or its base (the base is always tried first), cut at the first English (the language of the msgids, so nothing after it can be reached) and at twice `max_fallback_extras/0`. An English current locale stores nothing. The cap is stored with the list, so a miss reads both at once.

  Returns the locale names stored.
  """
  def put_fallback_extras(extras) do
    extras
    |> List.wrap()
    |> Enum.map(&extra_gettext_name/1)
    |> Enum.reject(&is_nil/1)
    |> then(&Fallback.put_extras(Bonfire.Common.Localise.Gettext, &1, max_fallback_extras()))
  end

  # nil if ex_cldr does not know it
  defp extra_gettext_name(nil), do: nil

  defp extra_gettext_name(extra) when is_binary(extra) or is_atom(extra) do
    case Bonfire.Common.Localise.Cldr.validate_locale(extra) do
      {:ok, tag} ->
        # for a language with no catalogue ex_cldr still names the closest Gettext locale it can find (eg. English for `zu`), which is not what the visitor reads, so a name in another language is no match
        requested_gettext_locale(tag) ||
          with name when not is_nil(name) <- tag.gettext_locale_name,
               name = name |> to_string() |> String.replace("-", "_"),
               true <- locale_language(name) == tag.language do
            name
          else
            _ -> nil
          end

      _ ->
        nil
    end
  end

  defp extra_gettext_name(%{} = tag), do: extra_gettext_name(tag.requested_locale_name)
  defp extra_gettext_name(_), do: nil

  @doc """
  The languages in an `Accept-Language` header value, in weight order, as the names the visitor sent. Entries ex_cldr cannot parse are left out. The first is the visitor's main language, which `put_fallback_extras/1` drops as a repeat of the current locale.
  """
  def accept_language_extras(header) when is_binary(header) do
    case Cldr.AcceptLanguage.parse(header, Bonfire.Common.Localise.Cldr) do
      {:ok, languages} ->
        for {quality, %{requested_locale_name: name}} <- languages,
            is_float(quality) or is_integer(quality),
            do: to_string(name)

      _ ->
        []
    end
  end

  def accept_language_extras(_), do: []

  # where the process keeps the browser's own extras (as sent), for the first render of a guest LiveView page, which runs in the process of the request
  @browser_extras_key :bonfire_localise_browser_extras

  @doc """
  For the `set_locale` plug, after `Cldr.Plug.SetLocale`: stores the browser's `Accept-Language` languages, then the instance's, with `put_fallback_extras/1` for the controller page, and keeps the browser's (cut at twice `max_fallback_extras/0`) in the process, for `browser_extras_from_process/0`. It never writes the session, so a guest stays cookieless: see `put_browser_extras_in_session/1` for a logged-in user.
  """
  def put_fallback_extras_from_conn(%Plug.Conn{} = conn) do
    browser = browser_extras(conn)

    Process.put(@browser_extras_key, browser)
    put_fallback_extras(browser ++ Bonfire.Common.Config.get([__MODULE__, :extra_locales], []))

    conn
  end

  @doc "The browser's extras that `put_fallback_extras_from_conn/1` kept in this process: what the on_mount of a guest LiveView page reads, as a guest has no session to read them from (and the first render, which is all a guest page does, runs in the process of the request)."
  def browser_extras_from_process, do: Process.get(@browser_extras_key, [])

  @doc """
  Writes the browser's `Accept-Language` extras to the session for the LiveView on_mount of a logged-in user (which does not see request headers), without choosing a locale. Only when they differ from what the session holds, so the session cookie is not rewritten on every response. Call it only for a request that has a login: a guest must get no session write.
  """
  def put_browser_extras_in_session(%Plug.Conn{} = conn) do
    browser = browser_extras(conn)

    if Map.has_key?(conn.private, :plug_session) and
         Plug.Conn.get_session(conn, fallback_session_key()) |> List.wrap() != browser do
      Plug.Conn.put_session(conn, fallback_session_key(), browser)
    else
      conn
    end
  end

  defp browser_extras(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-language")
    |> List.first()
    |> accept_language_extras()
    |> Enum.take(2 * max_fallback_extras())
  end

  defp locale_language(%{language: language}) when is_binary(language), do: language

  defp locale_language(locale),
    do: locale |> to_string() |> String.split(["-", "_"]) |> List.first()

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
          put_requested_gettext_locale(desired, best)
          put_fallback_extras(desired)
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
