defmodule Bonfire.Common.Localise.GettextContextTest do
  @moduledoc """
  Covers gettext `msgctxt` handling: a contextual lookup must fall back to the context-less
  translation rather than to English, so that adding a context to an already-translated string
  never regresses a locale.

  Only a subset of locales is compiled outside `:prod` (see `:allowed_locales` in
  `Bonfire.Common.Localise.Gettext`, derived from the CLDR `:locales` config). A test written
  against a locale that is *not* compiled finds no translations and passes against English — which
  is precisely the failure mode under test — so `test "the locale under test is actually compiled"`
  below guards that, and must not be deleted.
  """
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.Localise.Gettext, as: Backend
  alias Bonfire.Common.Localise.Gettext.Helpers

  @locale "fr"

  # any module in :bonfire_boundaries, so the derived gettext domain is "bonfire_boundaries"
  @boundaries_module Bonfire.Boundaries.RuntimeConfig

  setup do
    previous = Gettext.get_locale(Backend)
    Gettext.put_locale(Backend, @locale)
    on_exit(fn -> Gettext.put_locale(Backend, previous) end)
    :ok
  end

  test "the locale under test is actually compiled" do
    # without this, every assertion below would pass against the untranslated English msgid
    assert @locale in Gettext.known_locales(Backend),
           "#{@locale} is not compiled — known locales are #{inspect(Gettext.known_locales(Backend))}"
  end

  describe "localise_dynamic/2 (precondition)" do
    test "resolves a boundary verb to its translation" do
      # guards the fixture itself: if these stop being translated upstream, the fallback test
      # below would pass for the wrong reason
      assert Helpers.localise_dynamic("Follow", @boundaries_module) == "Suivre"
      assert Helpers.localise_dynamic("Boost", @boundaries_module) == "Partager"
    end
  end

  describe "localise_dynamic/3 (contextual lookup)" do
    test "falls back to the context-less translation when no contextual one exists" do
      # the failure mode being guarded against: a plain contextual lookup finds no contextual
      # entry and silently yields the English msgid...
      assert Gettext.dpgettext(
               Backend,
               "bonfire_boundaries",
               "verb: action",
               "Follow"
             ) == "Follow"

      # ...whereas ours falls back to the context-less translation. If the fallback in
      # `translate_with_context/4` is removed, this assertion is what fails.
      assert Helpers.localise_dynamic("Follow", @boundaries_module, "verb: action") ==
               "Suivre"
    end
  end

  describe "domain pinning" do
    test "a verb name and summary resolve through the extension that declares them" do
      # regression: these were localised in `bonfire_ui_boundaries` components with `__MODULE__`,
      # which searched that extension's gettext domain for strings only ever extracted into
      # `bonfire_boundaries` — so every locale silently rendered the English
      verb = %{verb: "Follow", summary: "Follow a user or thread or whatever"}

      assert Bonfire.Boundaries.Verbs.verb_name(verb) == "Suivre"

      assert Bonfire.Boundaries.Verbs.verb_summary(verb) ==
               "Suivre un utilisateur, un fil de discussion ou autre"
    end

    test "a circle falls back to its localised stereotype name" do
      circle = %{stereotyped: %{named: %{name: "Local users"}}}

      assert Bonfire.Boundaries.Circles.stereotype_name(circle) ==
               Helpers.localise_dynamic("Local users", Bonfire.Boundaries.Circles)

      # a circle's own name is user text, not a translatable string, so it wins untouched
      assert Bonfire.Boundaries.Circles.circle_name(%{
               name: "my crew",
               stereotyped: %{named: %{name: "Local users"}}
             }) == "my crew"
    end
  end

  describe "localise_dynamic/3 (msgid passthrough)" do
    test "still returns the msgid when nothing is translated under either form" do
      assert Helpers.localise_dynamic(
               "Zzz not a real msgid",
               @boundaries_module,
               "verb: action"
             ) ==
               "Zzz not a real msgid"
    end
  end
end
