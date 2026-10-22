defmodule Bonfire.Common.VocabularyTest do
  @moduledoc """
  The wording of a kind of thing ("Top discussions", "Trending") as presets an instance picks from, a user overrides, and an instance extends with its own.

  The extension that owns a kind declares its presets, so what each ships (and that it reproduces today's strings) is tested there. These tests set presets of their own with `Process.put`, so they pin how `Vocabulary` resolves, translates and falls back whatever is installed.

  The text of those presets is real msgids on purpose: "Follow" has a French translation in the `:bonfire_boundaries` domain (the fixture `Bonfire.Common.Localise.GettextContextTest` relies on too), which the translation tests need.
  """
  # bare `ExUnit.Case` skips the `:backend` tag that `Bonfire.Common.DataCase` applies, so tag it here
  use ExUnit.Case, async: true
  @moduletag :backend

  alias Bonfire.Common.Localise.Gettext, as: Backend
  alias Bonfire.Common.Localise.Gettext.Helpers
  alias Bonfire.Common.Vocabulary

  @app :bonfire_common

  # any module in :bonfire_boundaries, so the msgids below are looked up in the "bonfire_boundaries" domain
  @declaring_module Bonfire.Boundaries.RuntimeConfig

  # "Follow" is translated to "Suivre" there, the other texts are in no .po file
  @translated "Follow"
  @untranslated "Not in any translation file"

  defp put_config(key, value), do: Process.put([@app, Vocabulary, key], value)
  defp choose(kind, preset_id), do: Process.put([@app, Vocabulary, kind], preset_id)

  defp user_choosing(kind, preset_id) do
    %{
      id: "vocabulary_test_user",
      settings: %Bonfire.Data.Identity.Settings{
        json: %{@app => %{Vocabulary => %{kind => preset_id}}}
      }
    }
  end

  setup do
    # the locale lives in the process dictionary too, so neither needs undoing
    Gettext.put_locale(Backend, "en")

    put_config(:kinds,
      topic: [
        module: @declaring_module,
        presets: %{
          topic: %{title: @translated, empty: "No topics"},
          buzzing: %{title: @untranslated, empty: "Nothing is buzzing"},
          quiet: %{title: "Quiet", empty: "Shh"}
        }
      ],
      other: [module: @declaring_module, presets: %{other: %{title: "Other"}}]
    )

    :ok
  end

  describe "choosing a preset" do
    test "a kind starts on the preset named like itself" do
      assert Vocabulary.preset_id(:topic, nil) == :topic
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @translated
    end

    test "the setting picks the preset, as an atom or as the string a form saves" do
      choose(:topic, :buzzing)
      assert Vocabulary.preset_id(:topic, nil) == :buzzing

      choose(:topic, "quiet")
      assert Vocabulary.preset_id(:topic, nil) == :quiet
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "Quiet"
    end

    test "the setting of one kind leaves the others alone" do
      choose(:topic, :buzzing)
      assert Vocabulary.preset_id(:other, nil) == :other
    end

    test "a user's own choice applies to them, and to nobody else" do
      user = user_choosing(:topic, "buzzing")

      assert Vocabulary.preset_id(:topic, current_user: user) == :buzzing
      assert Vocabulary.preset_id(:topic, nil) == :topic
    end

    test "an unknown id falls back to the default, without making an atom of it" do
      unknown = "no_such_preset_#{System.unique_integer([:positive])}"
      choose(:topic, unknown)

      assert Vocabulary.preset_id(:topic, nil) == :topic

      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    end
  end

  describe "kinds/0" do
    test "lists the kinds of the presets" do
      assert Enum.sort(Vocabulary.kinds()) == [:other, :topic]
    end

    test "lists a kind that exists only as custom presets, and it is usable" do
      put_config(:custom_presets, extra: %{solo: %{title: "On its own"}})
      choose(:extra, :solo)

      assert :extra in Vocabulary.kinds()
      assert Vocabulary.phrase(Vocabulary.preset(:extra, nil), :title) == "On its own"
    end
  end

  describe "custom presets" do
    setup do
      put_config(:custom_presets, topic: %{lunch: %{base: :topic, title: "The lunch table"}})
      choose(:topic, :lunch)

      :ok
    end

    test "give their own text, and the keys they leave out come from their base" do
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.phrase(preset, :title) == "The lunch table"
      assert Vocabulary.phrase(preset, :empty) == "No topics"
    end

    test "are listed after the built-in presets, whose default comes first" do
      assert Vocabulary.preset_id(:topic, nil) == :lunch
      assert Vocabulary.preset_ids(:topic) == [:topic, :buzzing, :quiet, :lunch]
    end
  end

  describe "for the settings page" do
    test "options/1 pairs the id, as a string, with the title of each preset, then offers one's own words" do
      assert Vocabulary.options(:topic) == [
               {"topic", @translated},
               {"buzzing", @untranslated},
               {"quiet", "Quiet"},
               {"custom", "Custom…"}
             ]
    end

    test "a kind with a single preset still offers one's own words" do
      assert Vocabulary.options(:other) == [{"other", "Other"}, {"custom", "Custom…"}]
    end

    test "phrase_keys/1 are the phrases of the kind's default preset, the title first" do
      assert Vocabulary.phrase_keys(:topic) == [:title, :empty]
      assert Vocabulary.phrase_keys(:other) == [:title]
    end

    test "phrase_keys/1 of a kind with no default preset is the title" do
      put_config(:custom_presets, extra: %{solo: %{title: "On its own"}})

      assert Vocabulary.phrase_keys(:extra) == [:title]
    end

    test "options/1 lists the custom presets too, and translates the built-in ones" do
      put_config(:custom_presets, topic: %{lunch: %{base: :topic, title: "The lunch table"}})
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.options(:topic) == [
               {"topic", "Suivre"},
               # the others are in no translation file: they keep their own English
               # rather than the default's translation, or the options would read the same
               {"buzzing", @untranslated},
               {"quiet", "Quiet"},
               {"lunch", "The lunch table"},
               {"custom", "Custom…"}
             ]
    end

    test "preset_for/2 gives a preset whether or not it is the one in use" do
      choose(:topic, :buzzing)

      assert Vocabulary.phrase(Vocabulary.preset_for(:topic, :quiet), :title) == "Quiet"
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @untranslated
    end

    test "kind_name/1 is the title of the kind's default preset, translated, or else the kind made readable" do
      assert Vocabulary.kind_name(:topic) == @translated

      Gettext.put_locale(Backend, "fr")
      assert Vocabulary.kind_name(:topic) == "Suivre"

      put_config(:custom_presets, a_new_kind: %{only: %{title: "Only"}})
      assert Vocabulary.kind_name(:a_new_kind) == "A new kind"
    end
  end

  describe "one's own words, typed in" do
    defp type(kind, phrases), do: Process.put([@app, Vocabulary, :custom, kind], phrases)

    setup do
      choose(:topic, "custom")

      :ok
    end

    test "are the phrases, and the default's are the rest" do
      type(:topic, %{title: "My own"})
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.preset_id(:topic, nil) == :custom
      assert Vocabulary.phrase(preset, :title) == "My own"
      assert Vocabulary.phrase(preset, :empty) == "No topics"

      type(:topic, %{title: "My own", empty: "Quiet, please"})
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.phrase(preset, :title) == "My own"
      assert Vocabulary.phrase(preset, :empty) == "Quiet, please"
    end

    test "are never replaced by a translation, while the rest is translated" do
      type(:topic, %{empty: "Quiet, please"})
      Gettext.put_locale(Backend, "fr")
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.phrase(preset, :empty) == "Quiet, please"
      assert Vocabulary.phrase(preset, :title) == "Suivre"
    end

    test "are trimmed, and a blank one is left to the default" do
      type(:topic, %{title: "  My own \n", empty: "   "})
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.phrase(preset, :title) == "My own"
      assert Vocabulary.phrase(preset, :empty) == "No topics"
    end

    test "are read with string keys too, as they come back from saved settings" do
      type(:topic, %{"title" => "Mine"})

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "Mine"
    end

    test "are read from a keyword list, which is how an instance's saved settings are kept in config" do
      # a field left blank is saved as nil
      type(:topic, title: "Ours", empty: nil)
      preset = Vocabulary.preset(:topic, nil)

      assert Vocabulary.phrase(preset, :title) == "Ours"
      assert Vocabulary.phrase(preset, :empty) == "No topics"
    end

    test "ignore a phrase the kind does not have" do
      type(:topic, %{"no_such_phrase" => "x"})

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @translated
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :no_such_phrase) == nil
    end

    test "none typed, or only blank ones, is the default" do
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @translated

      type(:topic, %{title: "   "})
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @translated
    end

    test "a user's own apply to them, and to nobody else" do
      user = %{
        id: "vocabulary_test_user",
        settings: %Bonfire.Data.Identity.Settings{
          json: %{@app => %{Vocabulary => %{topic: "custom", custom: %{topic: %{title: "Mine"}}}}}
        }
      }

      assert Vocabulary.phrase(Vocabulary.preset(:topic, current_user: user), :title) == "Mine"
    end
  end

  describe "phrase/2" do
    test "is nil for a phrase no preset has" do
      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :no_such_phrase) == nil
    end

    test "is nil for a kind nobody declared" do
      assert Vocabulary.phrase(Vocabulary.preset(:no_such_kind, nil), :title) == nil
    end
  end

  describe "translation" do
    test "the fixture is translated: the locale is compiled and the msgid has a translation" do
      # without this, every assertion below would pass against English for the wrong reason
      assert "fr" in Gettext.known_locales(Backend)

      Gettext.put_locale(Backend, "fr")
      assert Helpers.localise_dynamic(@translated, @declaring_module) == "Suivre"
    end

    test "a built-in preset is translated in the domain of the module that declares it" do
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "Suivre"
    end

    test "a phrase the chosen preset has no translation for gives the translation of the kind's default" do
      choose(:topic, :buzzing)
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "Suivre"
    end

    test "in the source language that fallback does not apply, the chosen preset reads as written" do
      choose(:topic, :buzzing)

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == @untranslated
    end

    test "a phrase no preset has a translation for reads as the chosen preset wrote it" do
      choose(:topic, :buzzing)
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :empty) == "Nothing is buzzing"
    end

    test "the text of a custom preset is never replaced by a translation" do
      put_config(:custom_presets, topic: %{lunch: %{base: :topic, title: "The lunch table"}})
      choose(:topic, :lunch)
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "The lunch table"
    end

    test "a custom preset takes the translation of the base's text it leaves out" do
      put_config(:custom_presets, topic: %{bare: %{base: :topic}})
      choose(:topic, :bare)
      Gettext.put_locale(Backend, "fr")

      assert Vocabulary.phrase(Vocabulary.preset(:topic, nil), :title) == "Suivre"
    end
  end
end
