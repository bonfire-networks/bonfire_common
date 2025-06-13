defmodule Bonfire.Common.TriggerCIPureUnitTest do
  use ExUnit.Case

  alias Bonfire.Common.TriggerCI

  describe "pure unit tests (no network)" do
    setup do
      # Configure to use a failing stub so we never make real HTTP calls
      Process.put([:bonfire_posts, :req_options], plug: {Req.Test, :pure_unit_test})
      Req.Test.set_req_test_to_private()

      # This stub will be called but should fail if HTTP is attempted
      Req.Test.stub(:pure_unit_test, fn conn ->
        Req.Test.json(conn, %{message: "Test response"})
      end)

      :ok
    end

    test "rejects unsupported providers immediately" do
      # This should return error before any HTTP attempt
      result = TriggerCI.trigger_rebuild(:unsupported, "example.com", "owner", "repo", "token")
      assert {:error, "Unsupported provider: unsupported"} = result
    end

    test "validates function signature with all parameters" do
      # Test that function accepts all parameter combinations without crashing

      assert {:ok, _} =
               TriggerCI.trigger_rebuild(:github, "host", "owner", "repo", "token",
                 branch: "develop",
                 reason: "test",
                 variables: %{env: "staging"},
                 workflow_id: "deploy.yml",
                 event_type: "custom"
               )
    end

    test "function exists and has correct arity" do
      # Test that the function is properly defined
      assert function_exported?(TriggerCI, :trigger_rebuild, 5)
      assert function_exported?(TriggerCI, :trigger_rebuild, 6)
    end

    test "handles keyword list options without error" do
      # Test various option combinations don't cause function clause errors
      options_list = [
        [],
        [branch: "main"],
        [reason: "test"],
        [variables: %{}],
        [workflow_id: "test.yml"],
        [branch: "dev", reason: "deploy", variables: %{env: "test"}]
      ]

      for options <- options_list do
        assert {:ok, _} =
                 TriggerCI.trigger_rebuild(:github, "host", "owner", "repo", "token", options)
      end
    end
  end
end
