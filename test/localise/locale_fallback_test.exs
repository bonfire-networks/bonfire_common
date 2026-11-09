defmodule Bonfire.Common.Localise.LocaleFallbackTest do
  @moduledoc """
  A regional locale (`fr_FR`) shows its base language's (`fr`) translation for a string it has not translated itself, rather than English.

  Only a subset of locales is compiled outside `:prod` (see `:allowed_locales` in `Bonfire.Common.Localise.Gettext`), so the first test guards that both locales are compiled: without it the assertions below could pass against English.

  The fixture is the msgid "Events and gatherings" in the `bonfire_social` domain, translated in `fr` and left untranslated in `fr_FR`.
  """
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  # brings in `l/4`, as components have it
  use Bonfire.Common.Localise

  alias Bonfire.Common.Localise
  alias Bonfire.Common.Localise.Gettext, as: Backend
  alias Bonfire.Common.Localise.Gettext.Fallback
  alias Bonfire.Common.Localise.Gettext.Helpers
  alias Bonfire.Common.Vocabulary

  @domain "bonfire_social"
  @msgid "Events and gatherings"
  @translated "Manifestations et rassemblements"

  setup do
    previous = Gettext.get_locale(Backend)
    on_exit(fn -> Gettext.put_locale(Backend, previous) end)
    :ok
  end

  defp in_locale(locale), do: Gettext.put_locale(Backend, locale)

  describe "precondition" do
    test "both locales are compiled, and the fixture is translated in fr only" do
      assert "fr" in Gettext.known_locales(Backend)
      assert "fr_FR" in Gettext.known_locales(Backend)

      in_locale("fr")
      assert Gettext.dgettext(Backend, @domain, @msgid) == @translated
      assert {:ok, @translated} = Backend.lgettext("fr", @domain, nil, @msgid, %{})

      # the raw fr_FR catalogue, read from disk, has the entry with no translation
      po = Expo.PO.parse_file!("priv/localisation/fr_FR/LC_MESSAGES/#{@domain}.po")

      assert %{msgstr: msgstr} =
               Enum.find(po.messages, &(IO.iodata_to_binary(&1.msgid) == @msgid))

      assert IO.iodata_to_binary(msgstr) == ""
    end
  end

  describe "a regional locale falls back to its base language" do
    test "dgettext" do
      in_locale("fr_FR")
      assert Gettext.dgettext(Backend, @domain, @msgid) == @translated
    end

    test "lgettext reports a fallback hit as :default, so a caller still sees a miss in the requested locale" do
      assert Backend.lgettext("fr_FR", @domain, nil, @msgid, %{}) == {:default, @translated}
    end

    test "localise_dynamic" do
      in_locale("fr_FR")
      assert Helpers.localise_dynamic(@msgid, Bonfire.Social) == @translated
    end

    test "l/4, which is what components call" do
      in_locale("fr_FR")
      # the macro needs a literal msgid and a literal domain
      assert l("Events and gatherings", [], nil, "bonfire_social") == @translated
    end

    test "a plural miss falls back too" do
      # no plural is translated in fr and missing from fr_FR in the shipped catalogues, so the callback is called as a miss in fr_FR would, with an entry that fr translates
      msgid = "%{number_of_edits} edit"
      msgid_plural = "%{number_of_edits} edits"
      bindings = %{number_of_edits: 5}

      in_locale("fr")
      expected = Gettext.dngettext(Backend, "bonfire_ui_social", msgid, msgid_plural, 5, bindings)
      assert expected == "5 modifications"

      assert Backend.handle_missing_plural_translation(
               "fr_FR",
               "bonfire_ui_social",
               nil,
               msgid,
               msgid_plural,
               5,
               bindings
             ) == {:default, expected}
    end

    test "Vocabulary with fallback: false still reports it as untranslated" do
      in_locale("fr_FR")

      preset = %{
        raw: %{},
        chain: [%{title: @msgid}],
        module: Bonfire.Social
      }

      # the fallback hit is {:default, _}, which Vocabulary treats as a miss, so the preset's own text is returned
      assert Vocabulary.phrase(preset, :title, fallback: false) == @msgid

      # and for a locale that does have the translation it is found
      in_locale("fr")
      assert Vocabulary.phrase(preset, :title, fallback: false) == @translated
    end
  end

  describe "controls" do
    test "in fr, a string missing from fr stays English" do
      in_locale("fr")
      assert Gettext.dgettext(Backend, @domain, "Zzz not a real msgid") == "Zzz not a real msgid"
    end

    test "in en, any msgid comes back unchanged" do
      in_locale("en")
      assert Gettext.dgettext(Backend, @domain, @msgid) == @msgid
    end

    test "in fr_FR, a string missing from both stays English" do
      in_locale("fr_FR")
      assert Gettext.dgettext(Backend, @domain, "Zzz not a real msgid") == "Zzz not a real msgid"
    end

    test "a fr_FR translation that exists is used over fr's" do
      # the two catalogues word this one differently
      in_locale("fr")
      assert Gettext.dgettext(Backend, "bonfire_ui_social", "Filter") == "Filtrer"

      in_locale("fr_FR")
      assert Gettext.dgettext(Backend, "bonfire_ui_social", "Filter") == "Filtre"
      assert {:ok, "Filtre"} = Backend.lgettext("fr_FR", "bonfire_ui_social", nil, "Filter", %{})
    end
  end

  # "Other languages I understand": after the regional -> base step, a miss tries the user's extra languages, in order.
  # The fixture is "3 days ago" in `bonfire_ui_common`: translated in `it` only (not in `fr`, `fr_FR` or `es`), and "Active", translated in both `it` and `es`.
  # "DeepL API Key" is in `bonfire_translation`, a domain that only `it` has a catalogue for (not `es`, `fr`, `fr_FR`).
  describe "extras (other languages I understand)" do
    @extra_domain "bonfire_ui_common"
    @italian_only "3 days ago"
    @italian_only_it "3 giorni fa"
    @both "Active"
    @both_it "Attivo"
    @both_es "Activo"
    @it_only_domain "bonfire_translation"
    @it_only_domain_msgid "DeepL API Key"
    @it_only_domain_it "Chiave API DeepL"
    @cap_key [:bonfire_common, Bonfire.Common.Localise, :max_fallback_extras]

    defp dget(domain, msgid), do: Gettext.dgettext(Backend, domain, msgid)

    defp with_extras(locale, extras) do
      in_locale(locale)
      Localise.put_fallback_extras(extras)
    end

    test "precondition: the fixtures are translated where the tests below need them, and only there" do
      for locale <- ["it", "es", "fr", "fr_FR"] do
        assert locale in Gettext.known_locales(Backend)
      end

      in_locale("it")
      assert dget(@extra_domain, @italian_only) == @italian_only_it
      assert dget(@extra_domain, @both) == @both_it
      assert dget(@it_only_domain, @it_only_domain_msgid) == @it_only_domain_it

      in_locale("es")
      assert dget(@extra_domain, @italian_only) == @italian_only
      assert dget(@extra_domain, @both) == @both_es

      # with no extras stored, fr_FR shows English for all of them
      in_locale("fr_FR")
      assert Fallback.extras() == []
      assert dget(@extra_domain, @italian_only) == @italian_only
      assert dget(@extra_domain, @both) == @both
      assert dget(@it_only_domain, @it_only_domain_msgid) == @it_only_domain_msgid

      assert Backend.has_catalogue?("it", @it_only_domain)
      refute Backend.has_catalogue?("es", @it_only_domain)
      refute Backend.has_catalogue?("fr_FR", @it_only_domain)
    end

    test "dgettext falls back to the extra" do
      with_extras("fr_FR", ["it"])
      assert dget(@extra_domain, @italian_only) == @italian_only_it
    end

    test "localise_dynamic and l/4 fall back to the extra" do
      with_extras("fr_FR", ["it"])
      assert Helpers.localise_dynamic(@italian_only, Bonfire.UI.Common) == @italian_only_it
      assert l("3 days ago", [], nil, "bonfire_ui_common") == @italian_only_it
    end

    test "lgettext reports a hit through an extra as :default" do
      with_extras("fr_FR", ["it"])

      assert Backend.lgettext("fr_FR", @extra_domain, nil, @italian_only, %{}) ==
               {:default, @italian_only_it}
    end

    test "a plural miss falls back to the extra too" do
      with_extras("fr", ["it"])
      msgid = "%{number_of_edits} edit"
      msgid_plural = "%{number_of_edits} edits"

      in_locale("it")

      expected =
        Gettext.dngettext(Backend, "bonfire_ui_social", msgid, msgid_plural, 5, %{
          number_of_edits: 5
        })

      assert expected != "5 edits"

      # a locale that does not have the entry itself, called as a miss would be
      assert Backend.handle_missing_plural_translation(
               "xx",
               "bonfire_ui_social",
               nil,
               msgid,
               msgid_plural,
               5,
               %{number_of_edits: 5}
             ) == {:default, expected}
    end

    test "Vocabulary with fallback: false still reports it as untranslated" do
      with_extras("fr_FR", ["it"])
      preset = %{raw: %{}, chain: [%{title: @italian_only}], module: Bonfire.UI.Common}

      assert Vocabulary.phrase(preset, :title, fallback: false) == @italian_only
    end

    test "extras are tried in order" do
      with_extras("fr_FR", ["es", "it"])
      assert dget(@extra_domain, @both) == @both_es

      with_extras("fr_FR", ["it", "es"])
      assert dget(@extra_domain, @both) == @both_it
    end

    test "an extra with no catalogue for the domain is skipped, and does not count towards the cap" do
      Process.put(@cap_key, 1)
      with_extras("fr_FR", ["es", "it"])

      assert Backend.has_catalogue?("es", @extra_domain)
      refute Backend.has_catalogue?("es", @it_only_domain)
      assert dget(@it_only_domain, @it_only_domain_msgid) == @it_only_domain_it
    end

    test "the chain stops at English, the source language" do
      with_extras("fr_FR", ["en", "it"])
      assert dget(@extra_domain, @italian_only) == @italian_only

      with_extras("en", ["it"])
      assert dget(@extra_domain, @italian_only) == @italian_only
    end

    test "a string missing everywhere returns the msgid once, without recursing through the extras" do
      with_extras("fr_FR", ["it", "es"])

      assert dget(@extra_domain, "Zzz not a real msgid") == "Zzz not a real msgid"

      # the marker that stops an extra's own miss from trying the extras again is cleared afterwards, and the extras are still stored
      assert Process.get(Bonfire.Common.Localise.Gettext.Fallback.guard_key()) == nil
      assert Fallback.extras() == ["it", "es"]
      assert dget(@extra_domain, @italian_only) == @italian_only_it
    end

    test "while an extra is being looked up, its own miss does not try the extras" do
      with_extras("fr_FR", ["it", "es"])
      args = ["fr_FR", @extra_domain, nil, @italian_only, %{}]
      assert apply(Backend, :handle_missing_translation, args) == {:default, @italian_only_it}

      Process.put(Bonfire.Common.Localise.Gettext.Fallback.guard_key(), true)
      assert apply(Backend, :handle_missing_translation, args) == {:default, @italian_only}
    end

    test "the cap limits how many extras with the domain are tried" do
      Process.put(@cap_key, 1)
      with_extras("fr_FR", ["es", "it"])
      # es has the domain but not the string, which uses up the cap before it
      assert dget(@extra_domain, @italian_only) == @italian_only

      Process.delete(@cap_key)
      with_extras("fr_FR", ["es", "it"])
      assert dget(@extra_domain, @italian_only) == @italian_only_it
    end

    test "the stored list drops invalid locales and ones with no catalogue, and renders with a cap of 1" do
      Process.put(@cap_key, 1)
      # xx is not a locale, zu is a real locale with no catalogue in the test build
      with_extras("fr_FR", ["xx", "zu", "it"])
      assert Fallback.extras() == ["it"]
      assert dget(@extra_domain, @italian_only) == @italian_only_it
    end

    test "the stored list is deduped, skips the main locale and its base, and is cut at twice the cap" do
      with_extras("fr_FR", ["fr", "fr_FR", "it", "it", "es"])
      assert Fallback.extras() == ["it", "es"]

      Process.put(@cap_key, 1)
      with_extras("fr", ["es", "it", "fr_FR"])
      assert Fallback.extras() == ["es", "it"]
    end

    test "an English main locale stores nothing" do
      with_extras("en", ["it"])
      assert Fallback.extras() == []
    end

    test "put_best_locale_match stores the rest of the desired locales as extras" do
      Localise.put_best_locale_match(["fr_FR", "it", "es"])
      assert Gettext.get_locale(Backend) == "fr_FR"
      assert Fallback.extras() == ["it", "es"]
      assert dget(@extra_domain, @italian_only) == @italian_only_it
    end

    test "put_locale resets the stored extras" do
      with_extras("fr_FR", ["it"])
      Localise.put_locale("fr_FR")
      assert Fallback.extras() == []
    end
  end

  describe "Fallback.chains/2" do
    @paths [
      "fr/LC_MESSAGES/a.po",
      "fr_FR/LC_MESSAGES/a.po",
      "fr_FR/LC_MESSAGES/b.po",
      "en/LC_MESSAGES/a.po",
      "en_GB/LC_MESSAGES/a.po"
    ]

    test "a regional locale falls back to its base when the base has the domain" do
      assert Fallback.chains(@paths, "en")[{"fr_FR", "a"}] == ["fr"]
    end

    test "skips a base with no catalogue for the domain" do
      assert Fallback.chains(@paths, "en")[{"fr_FR", "b"}] == []
    end

    test "skips the source language, even though it has a catalogue" do
      assert Fallback.chains(@paths, "en")[{"en_GB", "a"}] == []
    end

    test "a base locale has no parent" do
      assert Fallback.chains(@paths, "en")[{"fr", "a"}] == []
    end

    test "the rule follows the source language it is given" do
      assert Fallback.chains(@paths, "fr")[{"fr_FR", "a"}] == []
      assert Fallback.chains(@paths, "fr")[{"en_GB", "a"}] == ["en"]
    end

    # the msgids are written in English whatever an instance sets as its default locale, so an instance defaulting to `fr` must still send `fr_FR` to `fr`: the backend must not be able to pass its default locale in
    test "the source language defaults to English" do
      assert Fallback.chains(@paths)[{"fr_FR", "a"}] == ["fr"]
      assert Fallback.chains(@paths)[{"en_GB", "a"}] == []
    end

    test "works on full paths" do
      assert Fallback.chains(
               [
                 "/x/priv/localisation/fr/LC_MESSAGES/a.po",
                 "/x/priv/localisation/fr_FR/LC_MESSAGES/a.po"
               ],
               "en"
             )[{"fr_FR", "a"}] == ["fr"]
    end
  end
end
