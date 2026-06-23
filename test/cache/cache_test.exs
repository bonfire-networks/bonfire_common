defmodule Bonfire.Common.CacheTest do
  use Bonfire.Common.DataCase, async: true
  use Bonfire.Common.Utils

  alias Bonfire.Common.Cache

  doctest Bonfire.Common.Cache, import: true

  describe "maybe_apply_cached/3 standard `:cache` verb" do
    # a fn whose result changes on every invocation, so a cached read (same value) is
    # distinguishable from a recompute (new value). `async: false` forces synchronous cache
    # writes (Cachex writes async by default), so a read on the very next line sees the write.
    defp counter_fun do
      {:ok, agent} = start_supervised({Agent, fn -> 0 end})
      fn -> Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end) end
    end

    defp cached(f, key, extra \\ []),
      do: Cache.maybe_apply_cached(f, [], [cache_key: key, async: false] ++ extra)

    test "default serves from cache" do
      f = counter_fun()
      key = "cache_verb_default:#{System.unique_integer([:positive])}"

      first = cached(f, key)
      # subsequent reads return the cached value, not a recompute
      assert first == cached(f, key)
      assert first == cached(f, key)
    end

    test ":refresh recomputes + repopulates" do
      f = counter_fun()
      key = "cache_verb_refresh:#{System.unique_integer([:positive])}"

      before = cached(f, key)
      refreshed = cached(f, key, cache: :refresh)

      # refresh recomputed (new value) and stored it (next plain read matches the refreshed value)
      assert refreshed != before
      assert refreshed == cached(f, key)
    end

    test ":reset clears so the next read recomputes" do
      f = counter_fun()
      key = "cache_verb_reset:#{System.unique_integer([:positive])}"

      before = cached(f, key)
      cached(f, key, cache: :reset)

      assert cached(f, key) != before
    end

    test "cache: false bypasses the cache (recomputes every call, never writes)" do
      f = counter_fun()
      key = "cache_verb_bypass:#{System.unique_integer([:positive])}"

      a = cached(f, key, cache: false)
      b = cached(f, key, cache: false)
      # bypass always recomputes
      assert a != b
      # and never populated the cache, so the first normal read differs from the bypass values…
      normal = cached(f, key)
      assert normal not in [a, b]
      # …and is then cached
      assert normal == cached(f, key)
    end
  end
end
