defmodule Bonfire.Common.Text.Test do
  use Bonfire.Common.DataCase, async: false

  @tag :skip
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

  @tag :skip
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

  describe "maybe_markdown_to_html/2 sanitizer" do
    alias Bonfire.Common.Text

    test "generic_attributes allows rel on <a> to pass through ammonia" do
      html = ~s(<a href="/hashtag/bonfire" rel="tag ugc" class="hashtag">#bonfire</a>)

      result =
        Text.maybe_markdown_to_html(html,
          sanitize: true,
          link_rel: nil
        )

      assert result =~ ~r/rel="[^"]*\btag\b/
    end

    test "link_rel: nil does not strip existing rel on <a>" do
      html = ~s(<a href="/hashtag/bonfire" rel="tag ugc">#bonfire</a>)
      result = Text.maybe_markdown_to_html(html, sanitize: true, link_rel: nil)
      assert result =~ "rel="
    end
  end

  describe "replace_links/3" do
    alias Bonfire.Common.Text

    test "replaces href from replacements map" do
      html = ~s(<a href="/old">link</a>)
      result = Text.replace_links(html, %{"/old" => "/new"})
      assert {"a", [{"href", "/new"}], ["link"]} in result
    end

    test "leaves href unchanged when not in map" do
      html = ~s(<a href="/keep">link</a>)
      result = Text.replace_links(html, %{"/other" => "/new"})
      assert {"a", [{"href", "/keep"}], ["link"]} in result
    end

    test "adds nofollow noopener to external links without rel" do
      html = ~s(<a href="https://external.com">link</a>)
      [{"a", attrs, _}] = Text.replace_links(html, %{"_" => "_"})
      assert {"rel", "nofollow noopener"} in attrs
    end

    test "does not add nofollow to internal links" do
      html = ~s(<a href="/internal">link</a>)
      [{"a", attrs, _}] = Text.replace_links(html, %{"_" => "_"})
      refute List.keymember?(attrs, "rel", 0)
    end

    test "preserves existing rel on external links" do
      html = ~s(<a href="https://external.com" rel="ugc">link</a>)
      [{"a", attrs, _}] = Text.replace_links(html, %{"_" => "_"})
      assert {"rel", "ugc"} in attrs
    end
  end

  describe "prepare_links_for_local_render/1" do
    alias Bonfire.Common.Text

    test "adds LiveView navigation attrs to local links" do
      html = ~s(<a href="/local/path">local</a>)
      result = Text.prepare_links_for_local_render(html)
      assert result =~ ~s(data-phx-link="redirect")
      assert result =~ ~s(data-phx-link-state="push")
      assert result =~ ~s(href="/local/path")
    end

    test "adds rel=nofollow noopener to external links without rel" do
      html = ~s(<a href="https://example.com">external</a>)
      result = Text.prepare_links_for_local_render(html)
      assert result =~ ~s(rel="nofollow noopener)
      assert result =~ ~s(href="https://example.com")
    end

    test "adds nofollow noopener to external links with other rel" do
      html = ~s(<a href="https://example.com" rel="ugc">external</a>)
      result = Text.prepare_links_for_local_render(html)
      assert result =~ "nofollow noopener"
      assert result =~ ~s(href="https://example.com")
    end

    test "does not add nofollow to links that already have it" do
      html = ~s(<a href="https://example.com" rel="nofollow noopener ugc">external</a>)
      result = Text.prepare_links_for_local_render(html)
      refute result =~ "nofollow noopener nofollow"
    end

    test "does not add rel to hashtag local links" do
      html = ~s(<a href="/hashtag/elixir" class="hashtag" rel="tag ugc">#elixir</a>)
      result = Text.prepare_links_for_local_render(html)
      assert result =~ ~s(data-phx-link="redirect")
      assert result =~ ~s(rel="tag ugc")
      refute result =~ "nofollow"
    end

    test "passes through non-http non-local links unchanged" do
      html = ~s(<a href="mailto:foo@bar.com">mail</a>)
      result = Text.prepare_links_for_local_render(html)
      assert result == html
    end
  end

  describe "prepare_links_for_remote_render/2 :markdown" do
    test "converts hashtag markdown link to HTML with class and rel" do
      md = "post with [#elixir](/hashtag/elixir) tag"

      result =
        Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, "https://example.com")

      assert result =~ ~s(class="hashtag")
      assert result =~ ~s(rel="tag ugc")
      assert result =~ ~s(href="https://example.com/hashtag/elixir")
      refute result =~ "[#elixir]"
    end

    test "makes other relative markdown links absolute without HTML conversion" do
      md = "[some link](/some/path)"

      result =
        Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, "https://example.com")

      assert result == "[some link](https://example.com/some/path)"
    end

    test "makes image markdown links absolute" do
      md = "![alt text](/images/pic.jpg)"

      result =
        Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, "https://example.com")

      assert result == "![alt text](https://example.com/images/pic.jpg)"
    end

    test "makes relative href attributes absolute for :html format" do
      html = ~s(<a href="/some/path">link</a>)

      result =
        Bonfire.Common.Text.prepare_links_for_remote_render(html, :html, "https://example.com")

      assert result =~ ~s(href="https://example.com/some/path")
    end
  end
end
