defmodule Bonfire.Common.Localise.Gettext.Fallback do
  @moduledoc """
  Works out, from the catalogues that exist, which base language a regional locale (eg `fr_FR`) falls back to for a string it has not translated.

  Gettext has no locale fallback of its own, so `Bonfire.Common.Localise.Gettext` consults the result of `chains/1` from its missing-translation callbacks. It is computed at compile time, so a miss costs one lookup at runtime.
  """

  # the language every `l()` msgid is written in
  @source_locale "en"

  # where the process keeps the user's extra languages, as `{[{locale, base}], cap}`, so a miss gets both with the one `Process.get` it needs
  @extras_key :bonfire_localise_fallback_extras
  # set while an extra is being looked up, so its own miss does not try the extras again
  @guard_key :bonfire_localise_fallback_guard

  @doc "The process dictionary key holding the extra languages stored by `put_extras/3`."
  def extras_key, do: @extras_key

  @doc "The process dictionary key that is set while an extra language is being looked up."
  def guard_key, do: @guard_key

  @doc """
  Maps `{locale, domain}` to the locales to try after `locale` has missed, for every catalogue in `po_paths` (paths ending in `<locale>/LC_MESSAGES/<domain>.po`).

  The only candidate is the base language, the part of the locale before the first `_`. It is kept only if it has a catalogue for the same domain, and is not the source language, the one the msgids are written in: looking a msgid up in its own language can only return the same words. That is English whatever an instance sets as its default locale, so the backend relies on the default here rather than passing its default locale, which would switch off `fr_FR` → `fr` on an instance defaulting to `fr`. Every other case gives `[]`. The chain only ever gets shorter, so following it cannot loop.
  """
  def chains(po_paths, source_locale \\ @source_locale) do
    catalogues = MapSet.new(po_paths, &locale_and_domain/1)
    source_locale = to_string(source_locale)

    Map.new(catalogues, fn {locale, domain} = key ->
      # the rule is shared with the coverage task, so the share shown in the pickers follows what is rendered
      case Mix.Tasks.Bonfire.LocaliseCoverage.parent(
             locale,
             source_locale,
             &MapSet.member?(catalogues, {&1, domain})
           ) do
        nil -> {key, []}
        parent -> {key, [parent]}
      end
    end)
  end

  @doc """
  Stores, in the current process, the languages to try for a string that the current locale of `backend` (and its base language) has not translated, for the missing-translation callbacks of `Bonfire.Common.Localise.Gettext` to read. `extras` are Gettext locale names in order of preference, `cap` is how many of them (those with a catalogue for the string's domain) a single miss tries.

  An extra is kept only if it or its base language has a catalogue in `backend` at all (`de_CH` is kept for `de`). The list is cut at the first English (the language of the msgids, so nothing after it can be reached), deduped, left out where it repeats the current locale or its base (the base is always tried first), and cut at twice `cap`. An English current locale stores nothing. The cap is stored with the list, so a miss reads both with one `Process.get`.

  Returns the locale names stored.
  """
  def put_extras(backend, extras, cap) do
    main = Gettext.get_locale(backend)

    entries =
      if language(main) == @source_locale do
        []
      else
        known = Gettext.known_locales(backend)
        main_base = base_locale(main)

        extras
        |> Enum.uniq()
        |> Enum.take_while(&(language(&1) != @source_locale))
        |> Enum.filter(&(&1 in known or base_locale(&1) in known))
        |> Enum.reject(&(&1 == main or &1 == main_base))
        |> Enum.take(2 * cap)
        |> Enum.map(&{&1, base_locale(&1)})
      end

    if entries == [] do
      Process.delete(@extras_key)
    else
      Process.put(@extras_key, {entries, cap})
    end

    Enum.map(entries, &elem(&1, 0))
  end

  @doc "The locale names stored by `put_extras/3` in the current process."
  def extras do
    case Process.get(@extras_key) do
      {entries, _cap} -> Enum.map(entries, &elem(&1, 0))
      _ -> []
    end
  end

  @doc "Forgets the stored extra languages."
  def delete_extras, do: Process.delete(@extras_key)

  @doc "The language of a locale name, eg `\"fr\"` for `\"fr_FR\"` or `\"fr-FR\"`."
  def language(locale), do: locale |> to_string() |> String.split(["-", "_"]) |> hd()

  # nil for a locale with no region
  defp base_locale(locale) do
    case String.split(locale, "_", parts: 2) do
      [base, _region] -> base
      _ -> nil
    end
  end

  defp locale_and_domain(path) do
    [locale, "LC_MESSAGES", file] = path |> Path.split() |> Enum.take(-3)
    {locale, Path.rootname(file, ".po")}
  end
end
