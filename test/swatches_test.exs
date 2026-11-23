defmodule Bonfire.Common.SwatchesTest do
  use ExUnit.Case, async: true

  @moduletag :backend

  alias Bonfire.Common.Enums
  alias Bonfire.Common.Swatches

  test "the swatches are Tailwind's 17 hues, and a name is valid only if it is one of them" do
    assert length(Swatches.names()) == 17
    assert "violet" in Swatches.names()
    assert Swatches.valid?("violet")
    assert Swatches.valid?(:violet)
    refute Swatches.valid?("beige")
    refute Swatches.valid?("#6965e0")
    refute Swatches.valid?(nil)
    refute Swatches.valid?("")
  end

  test "normalize/1 gives the name as a string, or nil for anything that is not a swatch" do
    assert Swatches.normalize(:violet) == "violet"
    assert Swatches.normalize("violet") == "violet"
    assert Swatches.normalize("beige") == nil
    assert Swatches.normalize(nil) == nil
    assert Swatches.normalize(%{}) == nil
  end

  test "class/1 is the CSS class that sets the swatch's ink and wash" do
    assert Swatches.class("violet") == "topic-violet"
    assert Swatches.class("beige") == nil
  end

  test "from_seed/1 gives the same swatch for the same seed, and spreads different seeds" do
    seed = "01HZZZZZZZZZZZZZZZZZZZZZZZ"
    assert Swatches.from_seed(seed) == Swatches.from_seed(seed)
    assert Swatches.valid?(Swatches.from_seed(seed))

    picked = for n <- 1..60, uniq: true, do: Swatches.from_seed("seed-#{n}")
    assert length(picked) > 5
  end

  test "Enums.pick_by_hash/2 picks the same item for the same seed, and none from an empty list" do
    assert Enums.pick_by_hash([:a, :b, :c], "x") == Enums.pick_by_hash([:a, :b, :c], "x")
    assert Enums.pick_by_hash([:a, :b, :c], "x") in [:a, :b, :c]
    assert Enums.pick_by_hash([], "x") == nil
  end
end
