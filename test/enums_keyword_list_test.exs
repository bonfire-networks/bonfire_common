defmodule Bonfire.Common.EnumsKeywordListTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.Enums

  describe "maybe_to_keyword_list/3, recursive" do
    # as `Bonfire.Common.Settings.LoadInstanceConfig` converts the instance's settings at boot, which hold the instance's compiled keywords
    test "leaves a struct inside the settings as it is" do
      compiled = ActivityPub.MRF.KeywordMatcher.compile(["spam"])

      assert [activity_pub: [mrf_keyword: [reject: ["spam"], reject_compiled: converted]]] =
               Enums.maybe_to_keyword_list(
                 %{activity_pub: %{mrf_keyword: %{reject: ["spam"], reject_compiled: compiled}}},
                 true,
                 false
               )

      # still what its readers match on (`ActivityPub.MRF.KeywordPolicy`, `Bonfire.Boundaries.BlockKeywords.instance_match?/1`), or they would compile the list again
      assert converted == compiled
    end
  end
end
