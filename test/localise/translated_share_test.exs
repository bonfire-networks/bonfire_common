defmodule Bonfire.Common.Localise.TranslatedShareTest do
  @moduledoc """
  `translated_share/2` turns the `coverage.json` the coverage escript writes into the share of strings a user sees translated, over the domains of the apps the running flavour has loaded.

  The fixture has `bonfire_ui_common` (464 strings) and `bonfire_me` (320), plus a domain whose app is not loaded.
  """
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.Localise
  alias Bonfire.Common.Localise.Gettext.Coverage

  @path Path.expand("../support/localisation/share_fixture/coverage.json", __DIR__)
  @opts [path: @path, apps: [:bonfire_ui_common, :bonfire_me]]

  test "adds the translated and total counts over the loaded apps' domains" do
    assert (400 + 200) / (464 + 320) == Coverage.translated_share("fr", @opts)
  end

  test "a domain whose app is not loaded is left out of both sums" do
    with_all =
      Coverage.translated_share("fr",
        path: @path,
        apps: [:bonfire_ui_common, :bonfire_me, :not_loaded_app]
      )

    assert with_all != Coverage.translated_share("fr", @opts)
    assert (400 + 200 + 1000) / (464 + 320 + 1000) == with_all
  end

  test "a regional locale reads its own entry, which already holds the union with its base" do
    assert (410 + 220) / (464 + 320) == Coverage.translated_share("fr_FR", @opts)
  end

  test "takes the locale as the picker has it: an atom, with a hyphen" do
    assert Coverage.translated_share("fr_FR", @opts) == Coverage.translated_share(:"fr-FR", @opts)
  end

  test "English and its variants have no share" do
    assert nil == Coverage.translated_share("en", @opts)
    assert nil == Coverage.translated_share("en_GB", @opts)
    assert nil == Coverage.translated_share(:"en-GB", @opts)
  end

  test "a locale with no catalogue is 0" do
    assert 0 == Coverage.translated_share("zu", @opts)
  end

  test "an instance defaulting to fr still shows fr's real share" do
    Process.put([:bonfire_common, Bonfire.Common.Localise.Cldr, :default_locale], "fr")
    assert "fr" == Localise.default_locale()

    assert (400 + 200) / (464 + 320) == Coverage.translated_share("fr", @opts)
  end

  test "no coverage file means no share, rather than every language shown as untranslated" do
    assert nil ==
             Coverage.translated_share("fr",
               path: "/nonexistent/coverage.json",
               apps: [:bonfire_me]
             )
  end
end
