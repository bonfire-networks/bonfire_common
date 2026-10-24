defmodule Bonfire.Common.Vocabulary do
  @moduledoc """
  The words the UI uses for a kind of thing, as presets an instance picks from, a user overrides, and an instance extends with its own.

  A *kind* is a block or concept that can be worded differently ("Top discussions", "Trending"). A *preset* is one wording of it: a map of phrases (`%{title: ..., empty: ...}`). Every kind has a default preset named like itself, which reproduces the strings the UI had before the kind became configurable.

  The extension that owns a kind declares it from its `Bonfire.Common.ConfigModule`, with the msgids written as `l/1` so extraction finds them. Declaring `module: __MODULE__` makes that extension's gettext domain the one the phrases are looked up in, which is the domain `l/1` extracted them to (and where any existing translation of the same string already is):

      config :bonfire_common, Bonfire.Common.Vocabulary,
        kinds: [
          top_discussions: [
            module: __MODULE__,
            presets: %{
              top_discussions: %{title: l("Top discussions"), empty: l("No popular discussions yet.")},
              buzzing: %{title: l("What is buzzing"), empty: l("Nothing is buzzing yet.")}
            }
          ]
        ]

  `kinds` is a keyword list so that several extensions can each declare their own without replacing the others (config deep-merges keyword lists, not maps).

  An instance adds wordings of its own in its config. Their text is free text, so it is never translated. A key a custom preset leaves out comes from its `base`, a built-in preset of the same kind:

      config :bonfire_common, Bonfire.Common.Vocabulary,
        custom_presets: [
          top_discussions: %{
            school_yard: %{base: :top_discussions, title: "What do you hear in the school yard?"}
          }
        ]

  Which preset is in use is a setting, `[Bonfire.Common.Vocabulary, kind]`, so the usual cascade applies: the user, then their account, then the instance, then the default.

  The choice `"custom"` is words typed in on the settings page, stored at `[Bonfire.Common.Vocabulary, :custom, kind]` as a map of phrase to text. A phrase left blank is the default's. Like a custom preset, the text is never translated. (`kinds`, `custom_presets` and `custom` are keys of this config, so they can't be the id of a kind.)

  ## Translation

  A phrase falls back one phrase at a time. The chosen preset's text is used if it has a translation in the current locale. If not, the next built-in preset in the chain is tried: the base of a custom preset, then the kind's default preset. If nothing in the chain has a translation (which is always so in the source language), the chosen preset's text is used as written. So a preset that is only partly translated shows the default's translation for the phrases it lacks, instead of English, and terms can mix until the preset is fully translated.
  """

  require Bonfire.Common.Config
  require Bonfire.Common.Settings
  alias Bonfire.Common.Config
  alias Bonfire.Common.Settings
  alias Bonfire.Common.Localise.Gettext, as: Backend
  use Bonfire.Common.Localise

  # where the phrases are looked up when the kind declares no `module`
  @default_domain "bonfire_common"

  # the id of "write it yourself", which is not a preset an extension or the config declares
  @custom :custom

  @doc "Every kind that has presets, built in or custom."
  def kinds do
    Enum.uniq(Map.keys(declared_kinds()) ++ Map.keys(custom_presets()))
  end

  @doc """
  The ids of the presets of a kind that can be chosen: the kind's default first, then the other built-in ones, then the custom ones.
  """
  def preset_ids(kind) do
    built_in = built_in(kind) |> Map.keys() |> default_first(kind)

    custom =
      custom_presets()
      |> Map.get(kind, %{})
      |> Map.keys()
      |> Enum.reject(&(&1 in built_in))
      |> Enum.sort()

    built_in ++ custom
  end

  @doc """
  The id of the preset in use for a kind.

  `context` is whatever carries the viewer (a `@__context__`, or options like `[current_user: user]`), or `nil` for the instance's choice. A stored id that matches no preset (it was removed from config, say) gives the default. The match is on the string, so an id that arrives from a form never makes an atom.
  """
  def preset_id(kind, context \\ nil) do
    ids = preset_ids(kind)
    chosen = Settings.get([__MODULE__, kind], nil, opts(context))

    match_id(ids ++ [@custom], chosen) || default_id(ids, kind)
  end

  defp default_id(ids, kind), do: if(kind in ids, do: kind) || List.first(ids) || kind

  @doc "The preset used until a choice is made: the one named like the kind, else the first."
  def default_preset(kind), do: preset_for(kind, default_id(preset_ids(kind), kind))

  @doc """
  The preset in use for a kind, ready for `phrase/2`. See `preset_id/2` for `context`.

  When the choice is `:custom` (the user's or the instance's own words), the phrases typed in are the preset and the rest are the kind's default. With none typed in, it is the default.
  """
  def preset(kind, context \\ nil) do
    case preset_id(kind, context) do
      @custom -> own_words(kind, context)
      id -> preset_for(kind, id)
    end
  end

  defp own_words(kind, context) do
    default = default_preset(kind)
    stored = Settings.get([__MODULE__, @custom, kind], nil, opts(context))

    case typed_phrases(stored, kind) do
      typed when typed == %{} -> default
      # free text: never looked up in a translation file
      typed -> %{default | id: @custom, raw: Map.merge(default.raw, typed)}
    end
  end

  # an instance's settings are kept in config as keyword lists (`[title: "…", empty: nil]`), a user's as maps
  defp typed_phrases(stored, kind) when is_list(stored) do
    if Keyword.keyword?(stored), do: typed_phrases(Map.new(stored), kind), else: %{}
  end

  # only the phrases the kind has are read (so nothing typed in can make an atom), with atom or string keys since saved settings come back as either
  defp typed_phrases(%{} = stored, kind) do
    Enum.reduce(phrase_keys(kind), %{}, fn key, typed ->
      with text when is_binary(text) <- stored[key] || stored[to_string(key)],
           text = String.trim(text),
           true <- text != "" do
        Map.put(typed, key, text)
      else
        _ -> typed
      end
    end)
  end

  defp typed_phrases(_stored, _kind), do: %{}

  @doc """
  The phrases a kind has, which are those of its default preset, the title first. A kind with no default preset (one that only has custom presets) has the title.
  """
  def phrase_keys(kind) do
    case built_in(kind)[kind] do
      %{} = default ->
        keys = default |> Map.keys() |> Enum.sort()
        if :title in keys, do: [:title | List.delete(keys, :title)], else: keys

      _ ->
        [:title]
    end
  end

  @doc "The preset of a kind with that id, ready for `phrase/2`, whether or not it is the one in use."
  def preset_for(kind, id) do
    built_in = built_in(kind)
    default = built_in[kind]
    module = declared_kinds()[kind][:module]

    case custom_presets()[kind][id] do
      nil ->
        %{id: id, kind: kind, module: module, raw: %{}, chain: chain([built_in[id], default])}

      custom ->
        %{
          id: id,
          kind: kind,
          module: module,
          # free text: never looked up in a translation file
          raw: Map.delete(custom, :base),
          chain: chain([built_in[custom[:base]], default])
        }
    end
  end

  @doc """
  The presets of a kind as `{id, title}` pairs, in the order of `preset_ids/1`, then "Custom…" for words of one's own, for a select. The id is a string, as a form sends it back.

  A title with no translation in the current locale reads in English here rather than as the default's translation (see "Translation" above), or two options would read the same.
  """
  def options(kind) do
    presets =
      for id <- preset_ids(kind),
          do:
            {to_string(id),
             phrase(preset_for(kind, id), :title, fallback: false) || to_string(id)}

    presets ++ [{to_string(@custom), l("Custom…")}]
  end

  @doc """
  The name of a kind for the settings page: the title of its default preset, which is what the block is usually called. For a kind with no default preset (one that only has custom presets), its id made readable.
  """
  def kind_name(kind) do
    phrase(preset_for(kind, kind), :title, fallback: false) ||
      kind |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  @doc """
  The text of one phrase of a preset, translated into the current locale where there is a translation, or `nil` if no preset has the phrase.
  """
  def phrase(%{raw: raw, chain: chain} = preset, key, opts \\ []) do
    case Map.fetch(raw, key) do
      {:ok, text} ->
        text

      :error ->
        msgids = for %{} = built_in <- chain, is_binary(built_in[key]), do: built_in[key]

        # without the fallback only the preset's own text is tried, so it is never mistaken for another preset's
        msgids = if opts[:fallback] == false, do: Enum.take(msgids, 1), else: msgids

        translate_first(msgids, preset[:module])
    end
  end

  defp translate_first([], _module), do: nil

  defp translate_first([first | _] = msgids, module) do
    Enum.find_value(msgids, first, &translation(&1, module))
  end

  # `lgettext` tells a missing translation from a found one, which `dgettext` can't (it returns the msgid in both cases)
  defp translation(msgid, module) do
    case Backend.lgettext(Gettext.get_locale(Backend), domain(module), nil, msgid, %{}) do
      {:ok, translated} -> translated
      _ -> nil
    end
  end

  defp domain(nil), do: @default_domain

  defp domain(module) do
    case Application.get_application(module) do
      nil -> @default_domain
      otp_app -> to_string(otp_app)
    end
  end

  defp declared_kinds, do: Map.new(Config.get([__MODULE__, :kinds], []))

  defp custom_presets, do: Map.new(Config.get([__MODULE__, :custom_presets], []))

  @doc "The presets the extension that owns a kind declared for it, as a map of id to phrases. Custom presets are not in it."
  def built_in(kind), do: Map.new(declared_kinds()[kind][:presets] || %{})

  defp chain(presets), do: presets |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp default_first(ids, kind) do
    if kind in ids, do: [kind | List.delete(ids, kind) |> Enum.sort()], else: Enum.sort(ids)
  end

  defp match_id(_ids, nil), do: nil

  defp match_id(ids, chosen) when is_atom(chosen) or is_binary(chosen),
    do: Enum.find(ids, &(to_string(&1) == to_string(chosen)))

  defp match_id(_ids, _chosen), do: nil

  defp opts(nil), do: []
  defp opts(opts) when is_list(opts), do: opts
  defp opts(context), do: [context: context]
end
