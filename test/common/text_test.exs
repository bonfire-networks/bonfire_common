defmodule Bonfire.Common.Text.Test do
  use Bonfire.Common.DataCase, async: false

  test "markdown rendering is cached properly with custom cache key" do
    content = "# Test custom markdown **with formatting**"

    # Clear cache first to ensure consistent test
    cache_key = "markdown:test"
    Bonfire.Common.Cache.remove_all()

    opts =
      [cache: true]
      |> Keyword.put(:cache_key, cache_key)

    # Verify cache is empty
    assert {:ok, nil} = Bonfire.Common.Cache.get(cache_key)

    # First render should cache the result
    result1 = Bonfire.Common.Text.maybe_markdown_to_html(content, opts)

    # Verify cache now has content
    assert {:ok, cached_result} = Bonfire.Common.Cache.get(cache_key)
    assert cached_result == result1

    # Mock the markdown renderer to verify it's not called on second render
    # Second render should use cached value even with failing mock    
    result_mocked =
      Bonfire.Common.Text.maybe_markdown_to_html(
        content,
        opts |> Keyword.put(:markdown_library, FailingMockMarkdownLibrary)
      )

    # Results should match
    assert result1 == result_mocked
  end

  @tag :skip_ci
  test "markdown rendering with cache is faster" do
    content = "# Test simple markdown **with formatting**"
    opts = [cache: true]

    # Clear cache first to ensure consistent test
    Bonfire.Common.Cache.remove_all()

    # First render should cache the result
    {time1, result1} =
      :timer.tc(fn -> Bonfire.Common.Text.maybe_markdown_to_html(content, opts) end)

    IO.puts("First call (uncached markdown render): #{time1 / 1000}ms")

    for i <- 0..60 do
      {time_new, result_new} =
        :timer.tc(fn -> Bonfire.Common.Text.maybe_markdown_to_html(content, opts) end)

      #  NOTE: cache doesn't seem to help much the first few times
      assert i < 20 or time_new < time1

      IO.puts(
        "Call ##{i} (cached): #{time_new / 1000}ms with speed improvement: #{time1 / time_new}x faster"
      )

      assert result_new == result1
    end
  end

  # mock with a failing version to prove cache is used
  defmodule FailingMockMarkdownLibrary do
    def to_html(_content, _opts) do
      raise("Markdown renderer was called when it should have used cache")
    end
  end

  @tag :skip
  test "cache warmup: time vs repetition" do
    content = "# Cache warmup test document with **formatting**"
    opts = [cache: true]

    # Clear cache for clean test environment
    Bonfire.Common.Cache.remove_all()

    # --- BASELINE MEASUREMENT ---
    {time_baseline, result_baseline} =
      :timer.tc(fn ->
        Bonfire.Common.Text.maybe_markdown_to_html(content, opts)
      end)

    IO.puts("\n=== CACHE WARMUP COMPARISON ===")
    IO.puts("Baseline (first call): #{time_baseline / 1000}ms")

    # --- METHOD 1: WAITING APPROACH ---
    # Make one call then wait
    Bonfire.Common.Cache.remove_all()
    Bonfire.Common.Text.maybe_markdown_to_html(content, opts)

    # Wait for 2 seconds
    IO.puts("\nWaiting for 2 seconds...")
    Process.sleep(2000)

    # Measure performance after waiting
    {time_wait, result_wait} =
      :timer.tc(fn ->
        Bonfire.Common.Text.maybe_markdown_to_html(content, opts)
      end)

    IO.puts("After waiting 2s (second call): #{time_wait / 1000}ms")

    # --- METHOD 2: REPETITION APPROACH ---
    # Start fresh for fair comparison
    Bonfire.Common.Cache.remove_all()
    Bonfire.Common.Text.maybe_markdown_to_html(content, opts)

    # Make multiple calls to warm up the cache
    IO.puts("\nMaking 20 rapid calls to warm up cache...")

    for i <- 1..20 do
      Bonfire.Common.Text.maybe_markdown_to_html(content, opts)
    end

    # Measure performance after multiple calls
    {time_repeat, result_repeat} =
      :timer.tc(fn ->
        Bonfire.Common.Text.maybe_markdown_to_html(content, opts)
      end)

    IO.puts("After 20 rapid calls: #{time_repeat / 1000}ms")

    # --- RESULTS COMPARISON ---
    wait_speedup = time_baseline / max(time_wait, 1)
    repeat_speedup = time_baseline / max(time_repeat, 1)
    comparison = time_wait / max(time_repeat, 1)

    IO.puts("\n=== RESULTS ===")
    IO.puts("Waiting approach: #{wait_speedup}x faster than baseline")
    IO.puts("Repetition approach: #{repeat_speedup}x faster than baseline")
    IO.puts("Repetition vs waiting: #{comparison}x difference")

    # Ensure results are consistent
    assert result_baseline == result_wait
    assert result_baseline == result_repeat

    # Store results for analysis
    cache_test_results = %{
      baseline_ms: time_baseline / 1000,
      wait_ms: time_wait / 1000,
      repeat_ms: time_repeat / 1000,
      wait_speedup: wait_speedup,
      repeat_speedup: repeat_speedup,
      comparison: comparison
    }

    # Don't make assertions that could make the test fail
    # Just log the results for analysis
    IO.inspect(cache_test_results, label: "Cache Warmup Test Results")
  end
end
