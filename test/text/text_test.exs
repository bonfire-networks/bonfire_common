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

  # a real announcement post: a player alone in its paragraph, and a link on the line after its label (with a trailing space, as typed)
  @youtube "https://www.youtube.com/watch?v=q0BvUFpVJMs"
  @blog "https://bonfirenetworks.org/posts/for-the-things-we-can-only-do-together/"
  @announcement "Bonfire for Communities 1.1 is out today: For the things we can only do together.\n\n#{@youtube}\n\nGroups now federate, so you can find, follow and join one from a different Bonfire instance, from the threadiverse, and even from Mastodon, with the account you already have. Take your community back!\n\nBlog post: \n#{@blog}\n\n#bonfire #fediverse\n"

  # media placed in a body (an image, or a player's link, alone on its line) is cut out of the markdown so it can render as a component where it sits
  describe "standalone_urls/1" do
    alias Bonfire.Common.Text

    @u1 "https://example.com/files/redir/local/a.png"
    @u2 "https://video.example.com/w/x"

    test "finds an image or a link alone in a top-level paragraph" do
      md = "Intro\n\n![](#{@u1})\n\n[x](#{@u2})\n\nmore"

      assert Text.standalone_urls(md) == [@u1, @u2]
    end

    test "finds a bare URL alone in its paragraph" do
      assert Text.standalone_urls("Intro\n\n#{@u2}\n\nmore") == [@u2]
    end

    test "leaves out a URL in the middle of a sentence, in a list, a quote or code" do
      md = """
      see ![](#{@u1}) here and [x](#{@u2}) there

      - ![](#{@u1})

      > ![](#{@u1})

      ```
      ![](#{@u1})
      ```
      """

      assert Text.standalone_urls(md) == []
    end

    test "returns nothing for no body" do
      assert Text.standalone_urls(nil) == []
      assert Text.standalone_urls("") == []
    end

    test "finds a URL alone on its line, after a label line in the same paragraph" do
      assert Text.standalone_urls("Blog post: \n[x](#{@u2})") == [@u2]
      assert Text.standalone_urls("Blog post:\n#{@u2}\nmore") == [@u2]
    end

    test "finds a URL at the end of its line, after its label" do
      assert Text.standalone_urls("Blog post: #{@u2}") == [@u2]
      assert Text.standalone_urls("Blog post: [video.example.com/w/x](#{@u2})\nmore") == [@u2]
      assert Text.standalone_urls("Read [the post](#{@u2})") == [@u2]
    end

    # a real announcement post: a player alone in its paragraph, and a link on the line after its label
    test "finds both media of the announcement fixture" do
      assert Text.standalone_urls(@announcement) == [@youtube, @blog]
    end
  end

  describe "markdown_parts/3" do
    alias Bonfire.Common.Text

    defp html_of(md), do: String.trim(Text.maybe_markdown_to_html(md, []))

    test "cuts the body at each standalone URL in the set, rendering the parts between" do
      md = "Intro\n\n![](#{@u1})\n\nMid\n\n[x](#{@u2})\n\nEnd"

      assert [{:html, intro}, {:url, @u1}, {:html, mid}, {:url, @u2}, {:html, ending}] =
               Text.markdown_parts(md, MapSet.new([@u1, @u2]), [])

      assert String.trim(intro) == html_of("Intro")
      assert String.trim(mid) == html_of("Mid")
      assert String.trim(ending) == html_of("End")
    end

    test "cuts at a URL alone on its line, keeping its label line as its own part" do
      md = "Blog post: \n[x](#{@u2})\n\nEnd"

      assert [{:html, label}, {:url, @u2}, {:html, ending}] =
               Text.markdown_parts(md, MapSet.new([@u2]), [])

      assert label =~ "Blog post:"
      refute label =~ @u2
      assert String.trim(ending) == html_of("End")
    end

    test "cuts at a URL at the end of its line, keeping the label and dropping the URL's own text" do
      md = "Blog post: [video.example.com/w/x](#{@u2})\n\nEnd"

      assert [{:html, label}, {:url, @u2}, {:html, _}] =
               Text.markdown_parts(md, MapSet.new([@u2]), [])

      assert label =~ "Blog post:"
      refute label =~ "video.example.com"
    end

    test "keeps a named link's text before its card" do
      assert [{:html, label}, {:url, @u2}] =
               Text.markdown_parts("Read [the post](#{@u2})", MapSet.new([@u2]), [])

      assert label =~ "the post"
    end

    test "cuts the same-line variant of the announcement fixture too" do
      md = String.replace(@announcement, "Blog post: \n", "Blog post: ")

      assert [{:html, _}, {:url, @youtube}, {:html, middle}, {:url, @blog}, {:html, _}] =
               Text.markdown_parts(md, MapSet.new([@youtube, @blog]), [])

      assert middle =~ "Blog post:"
      refute middle =~ "bonfirenetworks.org"
    end

    test "cuts the announcement fixture at its player and its blog link" do
      assert [{:html, intro}, {:url, @youtube}, {:html, middle}, {:url, @blog}, {:html, tags}] =
               Text.markdown_parts(@announcement, MapSet.new([@youtube, @blog]), [])

      assert intro =~ "Bonfire for Communities 1.1"
      assert middle =~ "Take your community back!"
      assert middle =~ "Blog post:"
      assert tags =~ "#bonfire"
    end

    test "keeps a standalone URL that isn't in the set inside the HTML" do
      md = "Intro\n\n![](#{@u1})\n\n[x](#{@u2})"

      assert [{:html, html}, {:url, @u2}] = Text.markdown_parts(md, MapSet.new([@u2]), [])
      assert html =~ ~s(src="#{@u1}")
    end

    test "keeps an image in the middle of a sentence inside the HTML" do
      md = "a ![](#{@u1}) b"

      assert [{:html, html}] = Text.markdown_parts(md, MapSet.new([@u1]), [])
      assert html =~ ~s(src="#{@u1}")
    end

    test "with an empty set, gives the whole body as one HTML part, as maybe_markdown_to_html does" do
      md = "Intro\n\n![](#{@u1})"

      assert Text.markdown_parts(md, MapSet.new(), []) ==
               [{:html, Text.maybe_markdown_to_html(md, [])}]
    end

    test "a reference link used in one part and defined in another still links" do
      md = "See [the docs][1]\n\n![](#{@u1})\n\n[1]: https://example.org/docs"

      assert [{:html, html}, {:url, @u1}] = Text.markdown_parts(md, MapSet.new([@u1]), [])
      assert html =~ ~s(href="https://example.org/docs")
    end

    test "still sanitises each part" do
      # led by a word: a body that starts with `<` is taken as HTML and never reaches the markdown path
      md = "Intro <script>alert(1)</script>\n\n![](#{@u1})\n\n<img src=x onerror=alert(1)>"

      parts = Text.markdown_parts(md, MapSet.new([@u1]), [])

      assert {:url, @u1} in parts

      for {:html, html} <- parts do
        refute html =~ "<script"
        refute html =~ "onerror"
      end
    end

    test "hides a trailing hashtags paragraph only in the last part, when asked" do
      md = "Intro\n\n![](#{@u1})\n\nEnd\n\n[#tag](/hashtag/tag)"

      assert [{:html, _intro}, {:url, @u1}, {:html, ending}] =
               Text.markdown_parts(md, MapSet.new([@u1]), hide_trailing_hashtags: true)

      assert ending ==
               Text.maybe_markdown_to_html("End\n\n[#tag](/hashtag/tag)",
                 hide_trailing_hashtags: true
               )
    end
  end

  # a local post gives each URL that ends a line its own paragraph when published, so it federates with the URL on its own line, where another instance can place its media
  describe "own_paragraph_urls/1" do
    alias Bonfire.Common.Text

    @linked "[video.example.com/w/x](#{@u2})"

    test "puts a URL after its label in its own paragraph, bare or as Linkify writes it" do
      assert Text.own_paragraph_urls("Watch: #{@linked}") == "Watch:\n\n#{@linked}"
      assert Text.own_paragraph_urls("Watch: #{@u2}") == "Watch:\n\n#{@u2}"
    end

    test "puts a URL ending a paragraph in its own paragraph" do
      assert Text.own_paragraph_urls("Intro\n\nsee this #{@linked}.\n\nmore") ==
               "Intro\n\nsee this\n\n#{@linked}.\n\nmore"
    end

    # a URL glued to the text before it (eg. inside a broken link, or a bracket) isn't a word of its own: moving it would split what the author typed
    test "leaves a URL glued to the text before it as typed" do
      for md <- ["[a link](#{@u2}]", "see (#{@u2}", "x:#{@u2}"] do
        assert Text.own_paragraph_urls(md) == md
      end
    end

    # the spaces before the URL would be left trailing at the end of the line before it: dropped, tabs too
    test "drops the spaces or tabs before the URL it moves" do
      assert Text.own_paragraph_urls("Watch:  \t#{@u2}") == "Watch:\n\n#{@u2}"
    end

    test "puts a URL alone on a line of a longer paragraph in its own paragraph, and the lines after it in another" do
      assert Text.own_paragraph_urls("before\n#{@linked}\nafter") ==
               "before\n\n\n#{@linked}\n\nafter"
    end

    test "leaves a named link, a mention or a hashtag ending a line as typed" do
      for md <- [
            "Read [the post](#{@u2})",
            "thanks [@someone](https://example.com/@someone)",
            "Hello [#bonfire](/hashtag/bonfire)"
          ] do
        assert Text.own_paragraph_urls(md) == md
      end
    end

    test "leaves the announcement fixture's same-line variant with its blog link in its own paragraph" do
      md = String.replace(@announcement, "Blog post: \n", "Blog post: ")

      assert Text.standalone_urls(Text.own_paragraph_urls(md)) == [@youtube, @blog]
      assert Text.own_paragraph_urls(md) =~ "Blog post:\n\n#{@blog}"
    end

    test "leaves a URL already alone in its paragraph, in a sentence, a list, a quote or code as typed" do
      md = """
      Intro

      [x](#{@u2})

      see [x](#{@u2}) there

      - a [x](#{@u2})

      > a [x](#{@u2})

      ```
      a [x](#{@u2})
      ```
      """

      assert Text.own_paragraph_urls(md) == md
    end

    test "leaves no body as it is" do
      assert Text.own_paragraph_urls(nil) == nil
      assert Text.own_paragraph_urls("") == ""
    end
  end

  # the HTML twin of `markdown_parts/3`, for a body that isn't markdown (a remote post, an import): for now a cut is a link alone in its paragraph
  describe "markdown_parts/3 with an HTML body" do
    alias Bonfire.Common.Text

    @yt "https://www.youtube.com/watch?v=x&t=3"

    test "cuts at a link alone in its paragraph, keeping the paragraphs around it" do
      html = ~s(<p>Intro</p><p><a href="#{@u2}">#{@u2}</a></p><p>more</p>)

      assert [{:html, "<p>Intro</p>"}, {:url, @u2}, {:html, "<p>more</p>"}] =
               Text.markdown_parts(html, MapSet.new([@u2]), [])
    end

    test "cuts at a Mastodon link, its text split in spans" do
      html =
        ~s(<p>Intro</p>\n<p> <a href="#{@u2}" target="_blank" rel="nofollow noopener" translate="no"><span class="invisible">https://</span><span class="ellipsis">video.example.com/w/</span><span class="invisible">x</span></a> </p><p>more</p>)

      assert [{:html, "<p>Intro</p>\n"}, {:url, @u2}, {:html, "<p>more</p>"}] =
               Text.markdown_parts(html, MapSet.new([@u2]), [])
    end

    test "cuts at a bare link between paragraphs, as an imported embed leaves it" do
      html = ~s(<p>Intro</p><a href="#{@u2}">A video</a><p>more</p>)

      assert [{:html, "<p>Intro</p>"}, {:url, @u2}, {:html, "<p>more</p>"}] =
               Text.markdown_parts(html, MapSet.new([@u2]), [])
    end

    test "matches a URL with `&` as the HTML stores it" do
      html = ~s(<p>Intro</p><p><a href="https://www.youtube.com/watch?v=x&amp;t=3">video</a></p>)

      assert [{:html, "<p>Intro</p>"}, {:url, @yt}] =
               Text.markdown_parts(html, MapSet.new([@yt]), [])
    end

    test "doesn't cut a link ending a paragraph, in a sentence, in a quote or a list, or not in the set" do
      for html <- [
            ~s(<p>Watch: <a href="#{@u2}">#{@u2}</a></p>),
            ~s(<p>see <a href="#{@u2}">this</a> there</p>),
            ~s(<blockquote><p><a href="#{@u2}">#{@u2}</a></p></blockquote>),
            ~s(<ul><li><p><a href="#{@u2}">#{@u2}</a></p></li></ul>),
            ~s(<p>Intro</p><p><a href="#{@u1}">#{@u1}</a></p>)
          ] do
        assert [{:html, ^html}] = Text.markdown_parts(html, MapSet.new([@u2]), []), html
      end
    end
  end

  # a post may carry only the classes and `data-` attributes our own markup uses: any other class would let it use our styles (Tailwind classes that cover the screen with a fake dialog), any other `data-` attribute would let it reach our scripts' hooks
  describe "sanitizer classes and data attributes" do
    alias Bonfire.Common.Text

    # led by a word: `sanitize: true` is not applied to input that starts with `<` (its own finding), and these tests are about what the sanitiser keeps
    defp sanitize(html), do: Text.maybe_markdown_to_html("word " <> html, sanitize: true)

    test "the classes and data attributes our own markup uses are kept (control)" do
      for html <- [
            ~s(<a href="https://x.local/tag/a" class="hashtag" data-tag="a" rel="tag ugc">#a</a>),
            ~s(<a href="https://x.local/@b" class="u-url mention" data-user="b">@b</a>),
            ~s(<span class="h-card">b</span>),
            ~s(<span class="invisible">https://</span>),
            ~s(<img src="https://x.local/e.png" class="emoji" data-emoji=":e:" alt=":e:">),
            ~s(<span class="l-keyword" data-line="3">def</span>)
          ] do
        result = sanitize(html)

        for [_, value] <- Regex.scan(~r/(?:class|data-[a-z]+)="([^"]*)"/, html) do
          assert result =~ value, "#{inspect(value)} was dropped from #{html}: #{result}"
        end
      end
    end

    test "other classes are dropped" do
      result = sanitize(~s(<code class="fixed inset-0 z-50">x</code>))

      refute result =~ "fixed"
      refute result =~ "inset-0"
      refute result =~ "z-50"
    end

    test "other classes are dropped from an element whose own class is kept" do
      result = sanitize(~s(<a href="https://x.local/tag/a" class="hashtag fixed inset-0">#a</a>))

      assert result =~ "hashtag"
      refute result =~ "fixed"
      refute result =~ "inset-0"
    end

    test "other data attributes are dropped" do
      result =
        sanitize(
          ~s(<span data-tag="a" data-phx-link="redirect" data-evil="1" data-x-on-click="y">z</span>)
        )

      assert result =~ ~s(data-tag="a")
      refute result =~ "data-phx-link"
      refute result =~ "data-evil"
      refute result =~ "data-x-on-click"
    end
  end

  describe "maybe_sane_html/1 with no sanitiser" do
    alias Bonfire.Common.Text

    @payload "<img src=x onerror=alert(1)>"

    test "sanitises when the sanitiser is enabled (control)" do
      result = Text.maybe_sane_html("<p>ok</p>" <> @payload)

      assert result =~ "<p>ok</p>"
      refute result =~ "onerror"
    end

    test "escapes the text when the sanitiser is disabled, so it never comes back as HTML" do
      Process.put([:bonfire_common, Bonfire.Common.Text.SanitizeHTML, :modularity], :disabled)

      result = Text.maybe_sane_html(@payload)

      refute result =~ ~r/<img/i
      assert result =~ "&lt;img"
    end
  end

  describe "SanitizeHTML classes and data attributes" do
    alias Bonfire.Common.Text

    test "the classes our own markup uses are kept (control)" do
      for html <- [
            ~s(<span class="invisible">x</span>),
            ~s(<span class="mention">x</span>),
            ~s(<span class="h-card">x</span>),
            ~s(<span class="hashtag">x</span>)
          ] do
        assert Text.maybe_sane_html(html) == html
      end
    end

    test "other classes are dropped" do
      result = Text.maybe_sane_html(~s(<span class="fixed inset-0 z-50">x</span>))

      refute result =~ "fixed"
      refute result =~ "z-50"
    end

    test "other data attributes are dropped" do
      result = Text.maybe_sane_html(~s(<span data-evil="1" data-phx-link="redirect">x</span>))

      refute result =~ "data-evil"
      refute result =~ "data-phx-link"
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

  describe "prepare_links_for_remote_render/4 resolves relative links against a post's URL" do
    @base "https://origin.local/post/01ABC"

    test "markdown path-relative links resolve against the object URL" do
      md = "a [#research](hashtag/research) and a [page](notes/1) and ![pic](img/a.png)"

      assert Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, @base) ==
               "a [#research](https://origin.local/post/hashtag/research) and a [page](https://origin.local/post/notes/1) and ![pic](https://origin.local/post/img/a.png)"
    end

    test "markdown root-relative and protocol-relative links resolve against the object URL" do
      md = "[some link](/some/path) and [other](//other.local/x)"

      assert Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, @base) ==
               "[some link](https://origin.local/some/path) and [other](https://other.local/x)"
    end

    test "markdown absolute, mailto and in-page links are left alone" do
      md = "[a](https://else.local/x) [b](mailto:a@b.local) [c](#section) of some length"

      assert Bonfire.Common.Text.prepare_links_for_remote_render(md, :markdown, @base) == md
    end

    test "html path-relative, root-relative and protocol-relative hrefs resolve against the object URL" do
      html =
        ~s(<a href="hashtag/research">#research</a> <a href="/x">x</a> <a href="//other.local/y">y</a>)

      assert Bonfire.Common.Text.prepare_links_for_remote_render(html, :html, @base) ==
               ~s(<a href="https://origin.local/post/hashtag/research">#research</a> <a href="https://origin.local/x">x</a> <a href="https://other.local/y">y</a>)
    end

    test "html absolute, mailto and in-page hrefs are left alone" do
      html =
        ~s(<a href="https://else.local/x">a</a> <a href="mailto:a@b.local">b</a> <a href="#s">c</a>)

      assert Bonfire.Common.Text.prepare_links_for_remote_render(html, :html, @base) == html
    end
  end

  describe "extract_urls_from_html/2 mention/hashtag filtering" do
    alias Bonfire.Common.Text

    test "skips a Mastodon mention anchor (class u-url mention)" do
      html =
        ~s(<span class="h-card"><a href="https://mastodon.social/@bob" class="u-url mention">@bob</a></span>)

      assert {:ok, %{urls: []}} = Text.extract_urls_from_html(html)
    end

    test "skips a hashtag anchor (class mention hashtag, rel tag)" do
      html = ~s(<a href="https://mastodon.social/tags/x" class="mention hashtag" rel="tag">#x</a>)
      assert {:ok, %{urls: []}} = Text.extract_urls_from_html(html)
    end

    test "keeps a plain external link" do
      assert {:ok, %{urls: ["https://example.com/post"]}} =
               Text.extract_urls_from_html(~s(<a href="https://example.com/post">plain</a>))
    end

    test "keeps a plain link alongside a filtered mention" do
      html =
        ~s(<a href="https://mastodon.social/@bob" class="u-url mention">@bob</a> and <a href="https://example.com">link</a>)

      assert {:ok, %{urls: ["https://example.com"]}} = Text.extract_urls_from_html(html)
    end

    test "keeps a mention anchor when include_mentions: true" do
      html = ~s(<a href="https://mastodon.social/@bob" class="u-url mention">@bob</a>)

      assert {:ok, %{urls: ["https://mastodon.social/@bob"]}} =
               Text.extract_urls_from_html(html, include_mentions: true)
    end
  end

  describe "code block syntax highlighting" do
    test "keeps highlight classes through the sanitizer, with no inline styles" do
      html =
        Bonfire.Common.Text.maybe_markdown_to_html("```elixir\ndefmodule A do\nend\n```")

      assert html =~ ~s(<span class="l-keyword)
      refute html =~ "style="
    end

    test "a highlighted code block keeps its l-* and language-* classes through the sanitizer (control)" do
      code = "defmodule A do\n  def f(x), do: {:ok, \"s\" <> x} # c\nend"
      raw = Lumis.highlight!(code, language: "elixir", formatter: :html_linked)
      html = Bonfire.Common.Text.maybe_markdown_to_html("```elixir\n#{code}\n```")

      classes = fn html ->
        ~r/class="([^"]*)"/
        |> Regex.scan(html)
        |> Enum.flat_map(fn [_, c] -> String.split(c) end)
        |> MapSet.new()
      end

      assert MapSet.size(classes.(raw)) > 5
      assert html =~ "language-elixir"
      assert html =~ ~r/<pre class="[^"]*\blumis\b/
      # no class the highlighter emitted is dropped
      assert MapSet.difference(classes.(raw), classes.(html)) |> MapSet.to_list() == []
    end

    test "the generated class lists cover what the highlighter emits" do
      lists = Bonfire.Common.Text.sanitizer_classes()
      allowed = MapSet.new(lists["span"] ++ lists["pre"] ++ lists["code"])

      snippets = [
        {"elixir",
         "defmodule A do\n  @moduledoc \"d\"\n  def f(x, y) when is_atom(x), do: {:ok, ~r/a/ <> \"s#{1}\"} # c\nend"},
        {"javascript", "const f = (a) => { return a.b?.c ?? [1, 2.5, 'x', `t${a}`]; } // c"},
        {"rust", "fn main() { let x: &str = \"s\"; println!(\"{}\", x); } // c"},
        {"python", "@dec\nclass A:\n    def f(self, x=1): return f\"{x}\"  # c"},
        {"html", "<div class=\"a\" id=b>t</div><!-- c -->"},
        {"css", "a:hover > .b { color: #fff; margin: 1px !important; }"},
        {"bash", "for i in $(ls); do echo \"$i\" | grep -v x; done # c"},
        {"json", "{\"a\": [1, true, null]}"},
        {"markdown", "# h\n\n*em* **b** `c` [l](u)\n\n- i"}
      ]

      emitted =
        for {lang, code} <- snippets,
            html =
              Lumis.highlight!(code,
                language: lang,
                formatter: {:html_linked, line_numbers: true}
              ),
            [_, c] <- Regex.scan(~r/class="([^"]*)"/, html),
            class <- String.split(c),
            into: MapSet.new(),
            do: class

      assert MapSet.size(emitted) > 10
      missing = MapSet.difference(emitted, allowed) |> MapSet.to_list()
      assert missing == [], "highlighter classes not in the sanitiser lists: #{inspect(missing)}"
    end

    test "mask_markdown_code returns text without code unchanged" do
      text = ~s(no code here, just "quotes" & <b>tags</b> and @mentions)

      assert {^text, unmask} = Bonfire.Common.Text.mask_markdown_code(text)
      assert unmask.(text) == text
    end

    test "mask_markdown_code restores many code spans, including tokens that share a prefix" do
      text = Enum.map_join(0..11, " and ", &"`code #{&1} < \"x\"`")

      {masked, unmask} = Bonfire.Common.Text.mask_markdown_code(text)

      refute masked =~ "`"
      assert unmask.(masked) == text
    end

    test "code_syntax with line numbers makes each line linkable without JS" do
      html =
        Bonfire.Common.Text.code_syntax("defmodule A do\n  :ok\nend", "lib/a.ex",
          line_numbers: true,
          highlight_lines: %{lines: [2], class: "l-highlighted"}
        )

      assert html =~
               ~s(<span id="L1" class="l-line" data-line="1"><a href="#L1" class="l-line-number")

      assert html =~
               ~s(<span id="L2" class="l-line l-highlighted" data-line="2"><a href="#L2" class="l-line-number l-line-number-highlighted")

      assert html =~ ~s(<span id="L3" class="l-line" data-line="3">)
      refute html =~ ~s(<span class="l-line-number)
    end

    test "code_syntax highlights a source file with the same classes, keeping the `highlight` layout class" do
      html =
        Bonfire.Common.Text.code_syntax(~s|defmodule A do\n  IO.puts("x < y")\nend|, "lib/a.ex")

      assert html =~ ~r/<pre class="[^"]*\bhighlight\b/
      assert html =~ ~s(<span class="l-keyword)
      assert html =~ "&quot;x &lt; y&quot;" or html =~ ~s("x &lt; y")
      refute html =~ "&amp;"
    end
  end

  describe "maybe_render_templated/2" do
    test "renders variables and filters in a Liquid template" do
      assert Bonfire.Common.Text.maybe_render_templated(
               "Hello {{ name }}, {{ name | upcase }}!",
               %{"name" => "World"}
             ) == "Hello World, WORLD!"
    end

    test "renders a template whose quotes were HTML-escaped by the editor" do
      assert Bonfire.Common.Text.maybe_render_templated(
               "{% if name == &quot;World&quot; %}Hi {{ name }}{% endif %}",
               %{"name" => "World"}
             ) == "Hi World"
    end

    test "returns the content unchanged when the template can't be parsed" do
      assert Bonfire.Common.Text.maybe_render_templated("Hello {{ name", %{"name" => "World"}) ==
               "Hello {{ name"
    end

    test "returns content without template tags unchanged" do
      assert Bonfire.Common.Text.maybe_render_templated("Hello name", %{"name" => "World"}) ==
               "Hello name"
    end
  end
end
