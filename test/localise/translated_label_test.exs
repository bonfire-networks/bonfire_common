defmodule Bonfire.Common.Localise.TranslatedLabelTest do
  @moduledoc """
  `translated_label/2` turns a locale's share of translated strings (see `translated_share_test.exs`) into the words the language pickers show after its name, or `nil` when there is nothing to say.

  The fixture has one domain of 1000 strings and a locale at each boundary: 0, 6%, 10%, 31%, 95%, 99.9% and 100%.
  """
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.Localise.Gettext.Coverage

  @path Path.expand("../support/localisation/label_fixture/coverage.json", __DIR__)
  @opts [path: @path, apps: [:bonfire_common]]

  test "a locale that translates nothing says so" do
    assert "not translated yet" == Coverage.translated_label("ab", @opts)
  end

  test "below 10% is not given as a number" do
    assert "<10% translated" == Coverage.translated_label("ac", @opts)
  end

  test "from 10% it is rounded to the nearest 10" do
    assert "10% translated" == Coverage.translated_label("ad", @opts)
    assert "30% translated" == Coverage.translated_label("ae", @opts)
  end

  test "a share that is not 100% never shows as more than 90%" do
    assert "90% translated" == Coverage.translated_label("af", @opts)
    assert "90% translated" == Coverage.translated_label("ah", @opts)
  end

  test "100% is fully translated" do
    assert "fully translated" == Coverage.translated_label("ag", @opts)
  end

  test "English and its variants have nothing to say" do
    assert nil == Coverage.translated_label("en", @opts)
    assert nil == Coverage.translated_label(:"en-GB", @opts)
  end

  test "no coverage file has nothing to say, rather than every language shown as untranslated" do
    assert nil ==
             Coverage.translated_label("ab",
               path: "/nonexistent/coverage.json",
               apps: [:bonfire_common]
             )
  end

  test "takes the locale as the picker has it: an atom, with a hyphen" do
    assert Coverage.translated_label("ae", @opts) == Coverage.translated_label(:ae, @opts)
  end
end
