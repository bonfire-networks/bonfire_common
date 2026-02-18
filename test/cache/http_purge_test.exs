defmodule Bonfire.Common.Cache.HTTPPurgeTest do
  @moduledoc """
  Tests for `Bonfire.Common.Cache.HTTPPurge`.

  Verifies the dispatch API and the Null adapter (default in test env).
  The Null adapter is a no-op, so these tests confirm that:

  - `bust_http_urls/1` and `bust_http_tags/1` return `:ok` without crashing.
  - Each configured adapter implements the required callbacks.
  - The single-path shorthand for `bust_http_urls/1` works.
  """

  use ExUnit.Case, async: true

  alias Bonfire.Common.Cache.HTTPPurge
  alias Bonfire.Common.Cache.HTTPPurge.Null

  describe "Null adapter" do
    test "bust_urls/1 is a no-op and returns :ok" do
      assert Null.bust_urls(["/gen_avatar/testuser"]) == :ok
    end

    test "bust_tags/1 is a no-op and returns :ok" do
      assert Null.bust_tags(["gen_avatar/testuser"]) == :ok
    end

    test "bust_urls/1 handles an empty list" do
      assert Null.bust_urls([]) == :ok
    end

    test "bust_tags/1 handles an empty list" do
      assert Null.bust_tags([]) == :ok
    end
  end

  describe "adapters/0" do
    test "returns a non-empty list" do
      adapters = HTTPPurge.adapters()
      assert is_list(adapters)
      assert length(adapters) >= 1
    end

    test "each adapter exports bust_urls/1 and bust_tags/1" do
      for adapter <- HTTPPurge.adapters() do
        assert function_exported?(adapter, :bust_urls, 1),
               "#{adapter} must export bust_urls/1"

        assert function_exported?(adapter, :bust_tags, 1),
               "#{adapter} must export bust_tags/1"
      end
    end
  end

  describe "bust_http_urls/1" do
    test "accepts a single URL string" do
      assert HTTPPurge.bust_http_urls("/gen_avatar/testuser") == :ok
    end

    test "accepts a list of URL paths" do
      assert HTTPPurge.bust_http_urls(["/gen_avatar/alice", "/gen_avatar/bob"]) == :ok
    end

    test "accepts an empty list" do
      assert HTTPPurge.bust_http_urls([]) == :ok
    end
  end

  describe "bust_http_tags/1" do
    test "accepts a list of surrogate-key tags" do
      assert HTTPPurge.bust_http_tags(["gen_avatar/testuser"]) == :ok
    end

    test "accepts an empty list" do
      assert HTTPPurge.bust_http_tags([]) == :ok
    end
  end
end
