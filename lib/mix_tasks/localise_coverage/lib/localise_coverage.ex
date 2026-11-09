defmodule Mix.Tasks.Bonfire.LocaliseCoverage do
  @shortdoc "Counts how many strings each locale translates"

  @moduledoc """
  Counts, per locale and domain, how many of the source strings a locale translates, and writes the counts to `<dir>/coverage.json`, for the language picker to turn into a share.

      mix bonfire.localise_coverage [--dir priv/localisation] [--source-locale en]

  `--dir` holds the source catalogues (`<domain>.po`) and one folder per locale (`<locale>/LC_MESSAGES/<domain>.po`). `--source-locale` is the language the msgids are written in.

  The total of a domain is the live entries of its source catalogue (not the obsolete `#~` ones). A string is translated when its `msgstr` is non-empty (every `msgstr[n]` for a plural) and it is not `fuzzy`, which Gettext ignores too. Keys the source no longer has are not counted, so a lagging locale file cannot push a share over 100%.

  A regional locale (eg `fr_FR`) also counts the strings its base language (`fr`) translates, as the user sees them through the fallback. That is a union of keys, not a sum, so a string both translate counts once.

  It runs as an escript (see `just escript_common localise_coverage`), so it needs Elixir and `expo` but not a compiled Bonfire.
  """
  use Mix.Task

  # for running as escript
  def main(args), do: run(args)

  @doc false
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string, source_locale: :string])
    dir = Keyword.get(opts, :dir, "priv/localisation")
    source_locale = Keyword.get(opts, :source_locale, "en")

    source = source_keys(dir)
    locales = locales(dir)

    translated =
      Map.new(locales, fn locale ->
        {locale,
         Map.new(source, fn {domain, keys} ->
           {domain,
            locale |> chain(domain, locales, dir, source_locale) |> count(keys, dir, domain)}
         end)}
      end)

    path = Path.join(dir, "coverage.json")

    File.write!(
      path,
      encode(%{
        "total" => Map.new(source, fn {d, k} -> {d, MapSet.size(k)} end),
        "translated" => translated
      })
    )

    IO.puts("Wrote #{path}")
  end

  # `%{domain => MapSet of keys}` of the live source entries
  defp source_keys(dir) do
    dir
    |> Path.join("*.po")
    |> Path.wildcard()
    |> Map.new(fn path ->
      {Path.basename(path, ".po"), path |> parse() |> Enum.map(&key/1) |> MapSet.new()}
    end)
  end

  defp locales(dir) do
    dir
    |> Path.join("*/LC_MESSAGES")
    |> Path.wildcard()
    |> Enum.map(&(&1 |> Path.dirname() |> Path.basename()))
    |> Enum.sort()
  end

  # The locales whose translations a locale shows: itself, then its base language if that has a catalogue for the domain and is not the source language.
  defp chain(locale, domain, locales, dir, source_locale) do
    case parent(
           locale,
           source_locale,
           &(&1 in locales and File.exists?(po_path(dir, &1, domain)))
         ) do
      nil -> [locale]
      parent -> [locale, parent]
    end
  end

  @doc """
  The base language a regional locale falls back to (`fr_FR` -> `fr`), or `nil`.

  The base language is the part of the locale before the first `_`. It is kept only if `has_catalogue?` (given the base language) says it has a catalogue for the domain, and it is not the source language, the one the msgids are written in: looking a msgid up in its own language can only give the same words.

  This is the one place that rule lives. `Bonfire.Common.Localise.Gettext.Fallback.chains/2` uses it at runtime and this task uses it to count what a user sees, so the share shown can't drift from what is rendered. It sits here, not in Bonfire, because an escript cannot depend on Bonfire.
  """
  def parent(locale, source_locale, has_catalogue?) when is_function(has_catalogue?, 1) do
    parent = locale |> String.split("_", parts: 2) |> hd()

    if parent != locale and parent != source_locale and has_catalogue?.(parent), do: parent
  end

  @doc """
  Reads a `coverage.json` this task wrote: `{:ok, %{"total" => %{domain => count}, "translated" => %{locale => %{domain => count}}}}`, or `:error` if the file is missing or is not that shape.
  """
  def read(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"total" => %{}, "translated" => %{}} = coverage} <- JSON.decode(body) do
      {:ok, coverage}
    else
      _ -> :error
    end
  end

  @doc """
  The share (0 to 1) of the strings in `domains` that `locale` translates, from the result of `read/1`. A locale the file doesn't have, or domains with no strings, give 0.
  """
  def share(%{"total" => total, "translated" => translated}, locale, domains) do
    counts = translated[locale] || %{}
    all = domains |> Enum.map(&Map.get(total, &1, 0)) |> Enum.sum()

    if all == 0 or counts == %{},
      do: 0,
      else: Enum.sum(Enum.map(domains, &Map.get(counts, &1, 0))) / all
  end

  @doc "The domains `read/1` found strings for."
  def domains(%{"total" => total}), do: Map.keys(total)

  defp count(chain, source_keys, dir, domain) do
    chain
    |> Enum.flat_map(fn locale ->
      path = po_path(dir, locale, domain)

      if File.exists?(path),
        do: path |> parse() |> Enum.filter(&translated?/1) |> Enum.map(&key/1),
        else: []
    end)
    |> MapSet.new()
    |> MapSet.intersection(source_keys)
    |> MapSet.size()
  end

  defp po_path(dir, locale, domain), do: Path.join([dir, locale, "LC_MESSAGES", domain <> ".po"])

  defp parse(path) do
    case Expo.PO.parse_file(path) do
      {:ok, %{messages: messages}} -> Enum.reject(messages, & &1.obsolete)
      {:error, error} -> raise "Could not parse #{path}: #{inspect(error)}"
    end
  end

  defp key(%Expo.Message.Singular{msgctxt: ctxt, msgid: id}), do: {text(ctxt), text(id), nil}

  defp key(%Expo.Message.Plural{msgctxt: ctxt, msgid: id, msgid_plural: plural}),
    do: {text(ctxt), text(id), text(plural)}

  defp text(nil), do: nil
  defp text(parts), do: IO.iodata_to_binary(parts)

  defp translated?(%Expo.Message.Singular{msgstr: str} = message),
    do: not Expo.Message.has_flag?(message, "fuzzy") and text(str) != ""

  defp translated?(%Expo.Message.Plural{msgstr: strs} = message),
    do:
      not Expo.Message.has_flag?(message, "fuzzy") and map_size(strs) > 0 and
        Enum.all?(strs, fn {_n, str} -> text(str) != "" end)

  # keys sorted for stable diffs, one locale (or domain total) per line; `JSON.encode!/1` for the leaves
  defp encode(%{"total" => total, "translated" => translated}) do
    "{\n" <>
      "  \"total\": " <>
      object(total) <>
      ",\n" <>
      "  \"translated\": {\n" <>
      Enum.map_join(Enum.sort(translated), ",\n", fn {locale, counts} ->
        "    " <> JSON.encode!(locale) <> ": " <> object(counts)
      end) <>
      "\n  }\n}\n"
  end

  defp object(counts) do
    "{" <>
      Enum.map_join(Enum.sort(counts), ", ", fn {k, v} ->
        JSON.encode!(k) <> ": " <> JSON.encode!(v)
      end) <>
      "}"
  end
end
