defmodule Bonfire.Common.EnumsDeepMergeTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.Enums

  describe "deep_merge/3" do
    test "merges maps at every level of nesting" do
      assert Enums.deep_merge(
               %{a: %{b: %{c: %{d: 1, e: 2}}}, x: 1},
               %{a: %{b: %{c: %{d: 3, f: 4}}}, y: 2}
             ) == %{a: %{b: %{c: %{d: 3, e: 2, f: 4}}}, x: 1, y: 2}
    end

    test "a caller's own on_conflict is used, at the top level" do
      assert Enums.deep_merge(%{a: %{b: 1}}, %{a: %{c: 2}}, on_conflict: fn _k, l, _r -> l end) ==
               %{a: %{b: 1}}
    end

    test "concatenates lists unless replace_lists is set, at any depth" do
      assert Enums.deep_merge(%{a: %{b: [1, 2]}}, %{a: %{b: [2, 3]}}) == %{a: %{b: [1, 2, 3]}}

      assert Enums.deep_merge(%{a: %{b: [1, 2]}}, %{a: %{b: [3]}}, replace_lists: true) ==
               %{a: %{b: [3]}}
    end

    test "merges keyword lists nested in maps" do
      assert Enums.deep_merge(%{a: [x: 1, y: [z: 1]]}, %{a: [y: [w: 2]]}) ==
               %{a: [x: 1, y: [z: 1, w: 2]]}
    end
  end
end
