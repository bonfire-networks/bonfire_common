defmodule Bonfire.Common.Localise.LocaleFallbackBenchmark.Options do
  @moduledoc false
  # The comparison backends below must compile the same catalogues as `Bonfire.Common.Localise.Gettext`, so they take the same options.
  # The locales are those the real backend compiled, because the `:locales` app env is not the list the real backend saw when it compiled (it reads `:all` when this file is loaded).
  def backend_opts do
    [
      otp_app: :bonfire_common,
      default_locale:
        :bonfire_common
        |> Application.get_env(Bonfire.Common.Localise.Cldr, [])
        |> Keyword.get(:default_locale, "en"),
      allowed_locales: ["en" | Gettext.known_locales(Bonfire.Common.Localise.Gettext)],
      plural_forms: Bonfire.Common.Localise.Gettext.Plural,
      priv: Application.fetch_env!(:bonfire_common, :localisation_path),
      split_module_by: [:locale, :domain]
    ]
  end
end

defmodule Bonfire.Common.Localise.LocaleFallbackBenchmark.Baseline do
  @moduledoc false
  # No override: a miss returns the msgid, which is the behaviour before any fallback exists.
  use Gettext.Backend, Bonfire.Common.Localise.LocaleFallbackBenchmark.Options.backend_opts()
end

defmodule Bonfire.Common.Localise.LocaleFallbackBenchmark.Draft do
  @moduledoc false
  # The override drafted in https://github.com/bonfire-networks/bonfire-app/issues/1355: every miss asks `Cldr.Locale.fallback_locale_names/2` (which runs `Cldr.validate_locale`) and guards against loops with a `Process` dictionary entry holding a `MapSet`.
  # The draft as pasted in the issue does not compile (it refers to unbound `key` and `locale`) and never clears its loop-protection entry, so a second lookup of the same string in a process would be answered from the stale entry. This version keeps its per-miss work and clears the entry when the lookup finishes, and turns the CLDR names (`fr-FR`) into Gettext locale names (`fr_FR`), which the draft does not.
  use Gettext.Backend, Bonfire.Common.Localise.LocaleFallbackBenchmark.Options.backend_opts()

  def handle_missing_translation(locale, domain, msgctxt, msgid, bindings) do
    with_loop_protection({domain, msgctxt, msgid}, locale, {:default, msgid}, fn fallback ->
      case lgettext(fallback, domain, msgctxt, msgid, bindings) do
        {:ok, translation} -> translation
        {:missing_bindings, translation, _} -> translation
        {:default, _} -> nil
      end
    end)
  end

  def handle_missing_plural_translation(locale, domain, msgctxt, msgid, msgid_plural, n, bindings) do
    default = if n == 1, do: msgid, else: msgid_plural

    with_loop_protection(
      {domain, msgctxt, msgid, msgid_plural},
      locale,
      {:default, default},
      fn fallback ->
        case lngettext(fallback, domain, msgctxt, msgid, msgid_plural, n, bindings) do
          {:ok, translation} -> translation
          {:missing_bindings, translation, _} -> translation
          {:default, _} -> nil
        end
      end
    )
  end

  defp with_loop_protection(key, locale, default, gettext_fn) do
    attempted = Process.get(key, MapSet.new())

    if MapSet.member?(attempted, locale) do
      default
    else
      Process.put(key, MapSet.put(attempted, locale))

      try do
        case Cldr.Locale.fallback_locale_names(locale, Bonfire.Common.Localise.Cldr) do
          {:ok, names} ->
            case try_fallbacks(names, gettext_fn, key) do
              nil -> default
              translation -> {:ok, translation}
            end

          {:error, _} ->
            default
        end
      after
        if MapSet.size(attempted) == 0, do: Process.delete(key), else: Process.put(key, attempted)
      end
    end
  end

  defp try_fallbacks([], _gettext_fn, _key), do: nil
  defp try_fallbacks([:und | rest], gettext_fn, key), do: try_fallbacks(rest, gettext_fn, key)

  defp try_fallbacks([name | rest], gettext_fn, key) do
    fallback = name |> Atom.to_string() |> String.replace("-", "_")

    if MapSet.member?(Process.get(key, MapSet.new()), fallback) do
      try_fallbacks(rest, gettext_fn, key)
    else
      gettext_fn.(fallback) || try_fallbacks(rest, gettext_fn, key)
    end
  end
end

defmodule Bonfire.Common.Localise.LocaleFallbackBenchmark.Apiary do
  @moduledoc false
  # Logic from https://github.com/qoryai/apiary/blob/0bbeaacaaba86e0b035a9a129082c8e30fdba627/lib/apiary_web/gettext/fallback.ex
  # Copyright qoryai, licensed under the Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0). Modified: the `@modifier` handling is kept, the module is inlined as a backend, and the chain is split on every miss, with no skip for the default locale.
  use Gettext.Backend, Bonfire.Common.Localise.LocaleFallbackBenchmark.Options.backend_opts()

  def chain(locale) do
    language = locale |> String.split("@", parts: 2) |> hd()
    bare = language |> String.split("_", parts: 2) |> hd()
    Enum.uniq([language, bare]) -- [locale]
  end

  def next(locale), do: locale |> chain() |> List.first()

  @impl Gettext.Backend
  def handle_missing_translation(locale, domain, msgctxt, msgid, bindings) do
    case next(locale) do
      nil -> super(locale, domain, msgctxt, msgid, bindings)
      next -> lgettext(next, domain, msgctxt, msgid, bindings)
    end
  end

  @impl Gettext.Backend
  def handle_missing_plural_translation(locale, domain, msgctxt, msgid, plural, n, bindings) do
    case next(locale) do
      nil -> super(locale, domain, msgctxt, msgid, plural, n, bindings)
      next -> lngettext(next, domain, msgctxt, msgid, plural, n, bindings)
    end
  end
end

defmodule Bonfire.Common.Localise.LocaleFallbackBenchmarkTest do
  @moduledoc """
  Cost of a regional locale falling back to its base language (`fr_FR` to `fr`), per design, as a ratio against a plain `fr` hit in the same run.

  Compared in one run: a backend with no override (`Baseline`), the override drafted in issue 1355 (`Draft`), the published qoryai/apiary one (`Apiary`), and the real `Bonfire.Common.Localise.Gettext`. The bounds apply to the real backend. `Draft` must exceed the `B1` bound, which shows the benchmark tells the designs apart.

  Scenarios, each a lookup in `bonfire_social` unless noted:

  - `B1`: an English msgid looked up in `en`. There is no `en` catalogue, so every lookup is a miss; this is every string on an English page.
  - `B2`: an `fr_FR` miss that the `fr` parent translates (`"Events and gatherings"`).
  - `B3`: an `fr_FR` miss that `fr` does not translate either. `fr` has every domain `fr_FR` has (the only difference is `bonfire_geolocate`, which only `fr` has), so a domain that `fr` lacks does not exist; the missing-domain case (`B3 domain`) is a made-up domain name instead, which approximates it.
  - `B4`: an `fr_FR` hit.

  Excluded from the normal suite (`@moduletag :benchmark`).

  Run: `just test extensions/bonfire_common/test/localise/locale_fallback_benchmark_test.exs --only benchmark`
  """
  use ExUnit.Case, async: false

  @moduletag :backend
  @moduletag :benchmark
  @moduletag timeout: :infinity

  alias Bonfire.Common.Localise.LocaleFallbackBenchmark.{Apiary, Baseline, Draft}

  @domain "bonfire_social"
  @backends [
    {"baseline", Baseline},
    {"draft", Draft},
    {"apiary", Apiary},
    {"real", Bonfire.Common.Localise.Gettext}
  ]

  # Ratio against an `fr` hit, for the real backend. A miss costs 6 to 13 times a hit even with no override (it goes through the missing-translation callback and interpolation), so the bounds are not close to 1. They were set from the no-override backend's ratios over several runs on a loaded machine, where the same code moved by up to 1.7 times between runs. B1 (an English lookup) is printed but not asserted: the no-override backend itself measured above any bound tight enough to separate the drafted override (12.1 against the draft's 11.8 to 16.2), so the ratio's noise can't carry an assertion there. The page benchmark below asserts the English path against the no-override backend in the same run instead.
  @bounds %{b2: 6, b3: 15, b3_domain: 16, b4: 4}

  # A single lookup takes about as long as the clock tick, so each timed call does a batch of them and the medians are divided back down.
  @batch 200

  defp repeat(0, _backend, _locale, _domain, _msgid), do: :ok

  defp repeat(n, backend, locale, domain, msgid) do
    backend.lgettext(locale, domain, nil, msgid, %{})
    repeat(n - 1, backend, locale, domain, msgid)
  end

  defp text(backend, locale, domain, msgid) do
    case backend.lgettext(locale, domain, nil, msgid, %{}) do
      {:ok, text} -> text
      {:default, text} -> text
      {:missing_bindings, text, _} -> text
    end
  end

  # name => {locale, domain, msgid, expected texts}
  defp scenarios(fallback?) do
    # without a fallback an `fr_FR` miss comes back as the English msgid
    b2 =
      if fallback?,
        do: ["Manifestations et rassemblements"],
        else: ["Events and gatherings"]

    %{
      "fr hit" => {"fr", @domain, "Events and gatherings", ["Manifestations et rassemblements"]},
      "b1" => {"en", @domain, "Events and gatherings", ["Events and gatherings"]},
      "b2" => {"fr_FR", @domain, "Events and gatherings", b2},
      "b3" =>
        {"fr_FR", @domain, "Untranslated in every locale", ["Untranslated in every locale"]},
      "b3_domain" =>
        {"fr_FR", "no_such_domain", "Untranslated in every locale",
         ["Untranslated in every locale"]},
      "b4" => {"fr_FR", @domain, "(Curated activities)", ["(Activités sélectionnées)"]}
    }
  end

  test "regional fallback: cost per lookup, per design" do
    known = Gettext.known_locales(Bonfire.Common.Localise.Gettext)

    # `en` is not listed: it has no catalogue, which is what makes B1 all misses
    refute "en" in known

    for locale <- ["fr", "fr_FR"] do
      assert locale in known, "#{locale} is not compiled, known: #{inspect(known)}"
    end

    # whether a design falls back is read off the backend, so the real backend's row needs no change once it does
    falls_back = fn backend ->
      text(backend, "fr_FR", @domain, "Events and gatherings") ==
        "Manifestations et rassemblements"
    end

    expectations = %{
      Baseline => false,
      Draft => true,
      Apiary => true,
      Bonfire.Common.Localise.Gettext => falls_back.(Bonfire.Common.Localise.Gettext)
    }

    IO.puts(
      "\nreal backend falls back fr_FR to fr: #{expectations[Bonfire.Common.Localise.Gettext]}"
    )

    # correctness first, so the numbers are for lookups that resolve as intended
    for {label, backend} <- @backends,
        {name, {locale, domain, msgid, expected}} <- scenarios(expectations[backend]) do
      got = text(backend, locale, domain, msgid)

      assert got in expected,
             "#{label} #{name}: #{locale}/#{domain}/#{inspect(msgid)} gave #{inspect(got)}, expected one of #{inspect(expected)}"

      # a second call in the same process must agree (the draft keeps process state between calls)
      assert text(backend, locale, domain, msgid) == got, "#{label} #{name}: second call differs"

      # the hit rows must be found in the locale itself: `fr` and `fr_FR` word some strings identically, so a miss that falls back to `fr` would give the expected text and be timed as a hit
      if name in ["fr hit", "b4"] do
        assert {:ok, _} = backend.lgettext(locale, domain, nil, msgid, %{}),
               "#{label} #{name}: #{locale}/#{domain}/#{inspect(msgid)} is not a hit in #{locale}"
      end
    end

    jobs =
      for {label, backend} <- @backends,
          {name, {locale, domain, msgid, _}} <- scenarios(expectations[backend]),
          into: %{} do
        {"#{label} #{name}", fn -> repeat(@batch, backend, locale, domain, msgid) end}
      end

    suite =
      Benchee.run(jobs,
        warmup: 1,
        time: 3,
        print: [fast_warning: false, configuration: false]
      )

    # per lookup
    medians =
      Map.new(suite.scenarios, fn s -> {s.name, s.run_time_data.statistics.median / @batch} end)

    # A hit never reaches an override, so the four backends' `fr hit` rows time the same code; their medians differ only by machine noise (52 to 99 ns on a loaded machine). The reference is the median of the four, so one slow slot cannot move a ratio.
    hit_ns =
      @backends
      |> Enum.map(fn {label, _} -> medians["#{label} fr hit"] end)
      |> Enum.sort()
      |> then(fn [_, a, b, _] -> (a + b) / 2 end)

    ratio = fn label, name -> medians["#{label} #{name}"] / hit_ns end

    IO.puts(
      "\n=== median ns per lookup, and ratio against the fr hit (#{Float.round(hit_ns, 1)} ns, median of the four backends' fr hit rows) ==="
    )

    for {label, _} <- @backends do
      IO.puts("#{label}: fr hit = #{Float.round(medians["#{label} fr hit"], 1)} ns")

      for name <- ~w(b1 b2 b3 b3_domain b4) do
        IO.puts(
          "  #{name}: #{Float.round(medians["#{label} #{name}"], 1)} ns, #{Float.round(ratio.(label, name), 2)}x"
        )
      end
    end

    # the benchmark must separate the designs: the draft pays per-miss CLDR validation on every regional miss, which shows clearly on B2 (hundreds of times an fr hit), where B1's noise couldn't
    draft_b2 = ratio.("draft", "b2")

    assert draft_b2 > @bounds.b2,
           "draft b2 is #{Float.round(draft_b2, 2)}x, not above the #{@bounds.b2}x bound, so the benchmark cannot tell it from the real design"

    for {name, bound} <- @bounds do
      key = Atom.to_string(name)
      got = ratio.("real", key)

      assert got <= bound,
             "real #{key} is #{Float.round(got, 2)}x an fr hit, above the #{bound}x bound"
    end
  end
end

defmodule Bonfire.Common.Localise.LocaleFallbackPageBenchmarkTest do
  @moduledoc """
  Cost of the regional fallback on a whole page's worth of lookups, per design, using the strings the annotator recorded for three pages.

  The source catalogues (`priv/localisation/<domain>.po`) list the pages each string rendered on (`#. URLs:`). The replay looks up every string recorded for the post page, `/notifications` and `/feed/local` once, in sequence, in `en`, `fr` and `fr_FR`, on the backends of `locale_fallback_benchmark_test.exs` (`Baseline`, `Draft`, `Apiary` and the real `Bonfire.Common.Localise.Gettext`). One timed call is one page render's worth of distinct lookups; a real render repeats some strings, so the distinct count is a floor.

  The bounds apply to the real backend: its `fr_FR` page against the no-override backend's `fr` page, and its `en` page against the no-override backend's `en` page.

  Excluded from the normal suite (`@moduletag :benchmark`).

  Run: `just test extensions/bonfire_common/test/localise/locale_fallback_benchmark_test.exs --only benchmark`
  """
  use ExUnit.Case, async: false

  @moduletag :backend
  @moduletag :benchmark
  @moduletag timeout: :infinity

  alias Bonfire.Common.Localise.LocaleFallbackBenchmark.{Apiary, Baseline, Draft}

  @real Bonfire.Common.Localise.Gettext
  @backends [{"baseline", Baseline}, {"draft", Draft}, {"apiary", Apiary}, {"real", @real}]
  @locales ["en", "fr", "fr_FR"]
  @pages ["post", "/notifications", "/feed/local"]

  # Ratio of the real backend's page time against the no-override backend's page time, for `fr_FR` against `fr` and for `en` against `en`. Over three runs on a loaded machine the no-override-relative ratios measured 1.09 to 1.30 (`fr_FR`) and 0.96 to 1.25 (`en`); the bound leaves room above the top of those ranges. The drafted override measured about 38 to 47 here, so the bound also separates it.
  # `extras` is the real backend's `fr_FR` page with one extra language (`it`) stored, against its plain `fr_FR` page: each miss the page language and its base lack now also looks in `it`.
  # Over three runs it measured 1.12 to 1.26 (the bound leaves room above the top).
  @bounds %{fr_fr: 1.6, en: 1.6, extras: 1.6}

  @localisation_dir Path.expand("../../../../priv/localisation", __DIR__)

  # name of the page a recorded URL belongs to, or nil when it is not one of the benchmarked pages
  defp page_of(url) do
    case URI.parse(url).path do
      "/post/" <> id -> if Regex.match?(~r/\A[0-9A-Z]{26}\z/, id), do: "post"
      path when path in ["/notifications", "/feed/local"] -> path
      _ -> nil
    end
  end

  defp text(parts), do: parts |> List.wrap() |> IO.iodata_to_binary()

  # page => [{domain, msgctxt, msgid, msgid_plural | nil}]
  defp annotated_pages do
    for path <- Path.wildcard(Path.join(@localisation_dir, "*.po")),
        domain = Path.basename(path, ".po"),
        %{} = message <- Expo.PO.parse_file!(path).messages,
        comment <- message.extracted_comments,
        "URLs: " <> urls <- [String.trim(comment)],
        page <-
          urls |> String.split() |> Enum.map(&page_of/1) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        reduce: Map.new(@pages, &{&1, []}) do
      acc ->
        plural =
          case message do
            %Expo.Message.Plural{msgid_plural: plural} -> text(plural)
            _ -> nil
          end

        # a render passes a value for every `%{name}`, so the benchmark does too (a lookup missing one answers `{:missing_bindings, …}`); `count` is supplied by the plural lookup
        bindings =
          ~r/%\{(\w+)\}/
          |> Regex.scan(text(message.msgid) <> (plural || ""), capture: :all_but_first)
          |> Map.new(fn [name] -> {String.to_atom(name), "x"} end)

        entry = {
          domain,
          message.msgctxt && text(message.msgctxt),
          text(message.msgid),
          plural,
          bindings
        }

        Map.update!(acc, page, &[entry | &1])
    end
    |> Map.new(fn {page, entries} -> {page, entries |> Enum.uniq() |> Enum.reverse()} end)
  end

  defp lookup(backend, locale, {domain, msgctxt, msgid, nil, bindings}),
    do: backend.lgettext(locale, domain, msgctxt, msgid, bindings)

  defp lookup(backend, locale, {domain, msgctxt, msgid, plural, bindings}),
    do: backend.lngettext(locale, domain, msgctxt, msgid, plural, 2, Map.delete(bindings, :count))

  defp render_page(backend, locale, entries) do
    Enum.each(entries, &lookup(backend, locale, &1))
  end

  defp text_of(result) do
    case result do
      {:ok, text} -> text
      {:default, text} -> text
      {:missing_bindings, text, _} -> text
    end
  end

  # hit: the locale's own catalogue has it; fell back: `fr_FR` miss that the real backend answers from `fr`; missed: neither
  defp classify(entries, locale) do
    Enum.reduce(entries, %{hit: 0, fell_back: 0, missed: 0}, fn entry, acc ->
      case lookup(@real, locale, entry) do
        {:ok, _} ->
          Map.update!(acc, :hit, &(&1 + 1))

        {:default, _} ->
          if locale == "fr_FR" and match?({:ok, _}, lookup(@real, "fr", entry)),
            do: Map.update!(acc, :fell_back, &(&1 + 1)),
            else: Map.update!(acc, :missed, &(&1 + 1))
      end
    end)
  end

  test "regional fallback: cost per page render, per design" do
    pages = annotated_pages()

    IO.puts(
      "\nstrings per page (distinct): #{inspect(Map.new(pages, fn {p, e} -> {p, length(e)} end))}"
    )

    # correctness first, so the numbers are for lookups that resolve as intended
    for {page, entries} <- pages do
      assert length(entries) > 100, "#{page}: only #{length(entries)} annotated strings"

      assert Enum.any?(entries, &match?({_, _, _, plural, _} when not is_nil(plural), &1)) or
               page != "post"

      for entry <- entries do
        {_, _, msgid, plural, _} = entry

        # no `en` catalogue: every backend answers with the source text; for a plural, which of the two forms depends on the locale's plural rule, so either is accepted
        for {label, backend} <- @backends do
          got = text_of(lookup(backend, "en", entry))

          # the source text with its bindings filled in: `count` is n (2), the others are "x"
          filled = fn source ->
            source &&
              Regex.replace(~r/%\{(\w+)\}/, source, fn _, name ->
                if name == "count" and plural, do: "2", else: "x"
              end)
          end

          # (the drafted override answers a miss with the raw msgid, without filling in the bindings, so that is accepted too)
          assert got in [filled.(msgid), filled.(plural), msgid, plural],
                 "#{label} en #{page}: #{inspect(entry)} gave #{inspect(got)}, not the source text"
        end

        # a hit is the same on every backend, and the real backend never answers `fr` differently from the baseline
        assert lookup(@real, "fr", entry) == lookup(Baseline, "fr", entry)

        # the real backend's fr_FR answer is its own, or `fr`'s when it has none
        # (a lookup with a binding the benchmark does not supply answers `{:missing_bindings, text, _}`, so only the text is compared)
        fr_fr = lookup(@real, "fr_FR", entry)

        assert match?({:ok, _}, fr_fr) or match?({:missing_bindings, _, _}, fr_fr) or
                 text_of(fr_fr) == text_of(lookup(@real, "fr", entry)),
               "real fr_FR #{page}: #{inspect(entry)} gave #{inspect(fr_fr)}, not fr's answer"
      end
    end

    # with `it` as an extra, some of the strings `fr` and `fr_FR` miss are answered in Italian
    Gettext.put_locale(@real, "fr_FR")
    Bonfire.Common.Localise.put_fallback_extras(["it"])

    for {page, entries} <- pages do
      via_extras =
        Enum.count(entries, fn entry ->
          with {:ok, italian} <- lookup(@real, "it", entry),
               {:default, _} <- lookup(@real, "fr", entry) do
            lookup(@real, "fr_FR", entry) == {:default, italian}
          else
            _ -> false
          end
        end)

      IO.puts("#{page}: #{via_extras} strings answered through the extra it")

      assert via_extras > 0,
             "#{page}: no string is answered through the extra, so the row would measure nothing"
    end

    Bonfire.Common.Localise.put_locale("en")

    jobs =
      for {page, entries} <- pages,
          locale <- @locales,
          {label, backend} <- @backends,
          into: %{} do
        {"#{page} #{locale} #{label}", fn -> render_page(backend, locale, entries) end}
      end

    # `fr_FR` with the extra language `it` stored in the process that runs the job (a Benchee hook runs in it, outside the timed call)
    jobs =
      for {page, entries} <- pages, into: jobs do
        {"#{page} fr_FR+it real",
         {fn -> render_page(@real, "fr_FR", entries) end,
          before_each: fn input ->
            Gettext.put_locale(@real, "fr_FR")
            Bonfire.Common.Localise.put_fallback_extras(["it"])
            input
          end,
          after_each: fn _ -> Bonfire.Common.Localise.Gettext.Fallback.delete_extras() end}}
      end

    suite =
      Benchee.run(jobs,
        warmup: 1,
        time: 2,
        print: [fast_warning: false, configuration: false]
      )

    # microseconds per page
    medians =
      Map.new(suite.scenarios, fn s ->
        {s.name, s.run_time_data.statistics.median / 1000}
      end)

    IO.puts("\n=== median µs per page render's worth of lookups ===")

    for page <- @pages, locale <- @locales do
      counts = classify(pages[page], locale)

      IO.puts(
        "#{page} (#{length(pages[page])} strings) #{locale} [real: #{counts.hit} hit, #{counts.fell_back} fell back, #{counts.missed} missed]: " <>
          Enum.map_join(@backends, ", ", fn {label, _} ->
            "#{label} #{Float.round(medians["#{page} #{locale} #{label}"], 1)}"
          end)
      )
    end

    IO.puts("\n=== ratios ===")

    ratios =
      for page <- @pages do
        fr_fr = medians["#{page} fr_FR real"] / medians["#{page} fr baseline"]
        en = medians["#{page} en real"] / medians["#{page} en baseline"]
        gap = medians["#{page} fr_FR real"] - medians["#{page} fr real"]
        fr_fr_baseline = medians["#{page} fr_FR real"] / medians["#{page} fr_FR baseline"]

        IO.puts(
          "#{page}: real fr_FR / baseline fr #{Float.round(fr_fr, 2)}x, real en / baseline en #{Float.round(en, 2)}x, real fr_FR / baseline fr_FR #{Float.round(fr_fr_baseline, 2)}x, real fr_FR minus real fr #{Float.round(gap, 1)} µs, draft fr_FR / baseline fr #{Float.round(medians["#{page} fr_FR draft"] / medians["#{page} fr baseline"], 2)}x, apiary fr_FR / baseline fr #{Float.round(medians["#{page} fr_FR apiary"] / medians["#{page} fr baseline"], 2)}x"
        )

        {page, fr_fr, en}
      end

    extras_ratios =
      for page <- @pages do
        ratio = medians["#{page} fr_FR+it real"] / medians["#{page} fr_FR real"]

        IO.puts(
          "#{page}: real fr_FR with extra it #{Float.round(medians["#{page} fr_FR+it real"], 1)} µs, #{Float.round(ratio, 2)}x real fr_FR"
        )

        {page, ratio}
      end

    for {page, ratio} <- extras_ratios do
      assert ratio <= @bounds.extras,
             "#{page}: real fr_FR page with an extra language is #{Float.round(ratio, 2)}x the same page without, above the #{@bounds.extras}x bound"
    end

    for {page, fr_fr, en} <- ratios do
      assert fr_fr <= @bounds.fr_fr,
             "#{page}: real fr_FR page is #{Float.round(fr_fr, 2)}x the baseline fr page, above the #{@bounds.fr_fr}x bound"

      assert en <= @bounds.en,
             "#{page}: real en page is #{Float.round(en, 2)}x the baseline en page, above the #{@bounds.en}x bound"
    end
  end
end
