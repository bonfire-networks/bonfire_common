defmodule Bonfire.Common.Text.SanitizeImportedHTMLTest do
  @moduledoc """
  Articles imported from another site (Ghost, WordPress) keep their structure (figures and their captions, galleries, players, code blocks, and the source's own card classes), while anything that could run (scripts, styles, event attributes, forms, iframes, non-web URLs) is removed, as for any other post.
  """
  use ExUnit.Case, async: true

  alias Bonfire.Common.Text.SanitizeImportedHTML

  defp clean(html), do: SanitizeImportedHTML.sanitize(html)

  describe "kept" do
    test "a Ghost image card, with its caption, srcset and card classes" do
      html =
        ~s|<figure class="kg-card kg-image-card kg-width-wide kg-card-hascaption"><img src="https://blog.example.local/content/images/2024/01/a.jpg" class="kg-image" alt="A view" loading="lazy" width="2000" height="1333" srcset="https://blog.example.local/content/images/size/w600/2024/01/a.jpg 600w, https://blog.example.local/content/images/2024/01/a.jpg 2000w" sizes="(min-width: 1200px) 1200px"><figcaption>Seen from <a href="https://example.com/hill">the hill</a></figcaption></figure>|

      out = clean(html)

      assert out =~ ~s|<figure class="kg-card kg-image-card kg-width-wide kg-card-hascaption">|
      assert out =~ ~s|class="kg-image"|
      assert out =~ "srcset="
      assert out =~ "size/w600"
      assert out =~ ~s|sizes="(min-width: 1200px) 1200px"|
      assert out =~ ~s|loading="lazy"|

      assert out =~
               ~s|<figcaption>Seen from <a href="https://example.com/hill">the hill</a></figcaption>|
    end

    test "a Ghost gallery keeps its rows" do
      html =
        ~s|<figure class="kg-card kg-gallery-card kg-width-wide"><div class="kg-gallery-container"><div class="kg-gallery-row"><div class="kg-gallery-image"><img src="https://blog.example.local/content/images/b.jpg" alt=""></div></div></div></figure>|

      out = clean(html)

      assert out =~ ~s|<div class="kg-gallery-container">|
      assert out =~ ~s|<div class="kg-gallery-row">|
      assert out =~ ~s|<div class="kg-gallery-image">|
    end

    test "audio and video keep their source, and get controls (the source's own player needed its scripts)" do
      out =
        clean(
          ~s|<div class="kg-card kg-audio-card"><audio src="https://blog.example.local/content/media/a.mp3" preload="metadata"></audio></div><figure class="kg-card kg-video-card"><video src="https://blog.example.local/content/media/v.mp4" poster="https://blog.example.local/content/images/p.jpg" playsinline preload="metadata"></video></figure>|
        )

      assert out =~ ~r/<audio[^>]*src="https:\/\/blog\.example\.local\/content\/media\/a\.mp3"/
      assert out =~ ~r/<audio[^>]*controls/

      assert out =~
               ~r/<video[^>]*poster="https:\/\/blog\.example\.local\/content\/images\/p\.jpg"/

      assert out =~ ~r/<video[^>]*controls/
    end

    test "a WordPress image block, with its alignment and caption" do
      out =
        clean(
          ~s|<figure class="wp-block-image size-large alignleft"><img src="https://wp.example.local/wp-content/uploads/a-1024x683.jpg" alt="Market" class="wp-image-12"><figcaption class="wp-element-caption">The market</figcaption></figure>|
        )

      assert out =~ ~s|<figure class="wp-block-image size-large alignleft">|
      assert out =~ ~s|<figcaption class="wp-element-caption">The market</figcaption>|
    end

    test "superscript and subscript" do
      out = clean(~s|<p>E = mc<sup>2</sup> and H<sub>2</sub>O</p>|)

      assert out =~ "mc<sup>2</sup>"
      assert out =~ "H<sub>2</sub>O"
    end

    test "a text direction, only as ltr, rtl or auto" do
      out =
        clean(
          ~s|<p dir="rtl">مرحبا</p><div dir="ltr">a</div><span dir="auto">b</span><h2 dir="rtl">c</h2><li dir="rtl">d</li><blockquote dir="rtl">e</blockquote><p dir="evil">f</p>|
        )

      assert out =~ ~s|<p dir="rtl">مرحبا</p>|
      assert out =~ ~s|<div dir="ltr">a</div>|
      assert out =~ ~s|<span dir="auto">b</span>|
      assert out =~ ~s|<h2 dir="rtl">c</h2>|
      assert out =~ ~s|<li dir="rtl">d</li>|
      assert out =~ ~s|<blockquote dir="rtl">e</blockquote>|
      # the control: any other value goes, the paragraph stays
      assert out =~ "<p>f</p>"
      refute out =~ "evil"
    end

    test "a link's rel, token by token" do
      out =
        clean(
          ~s|<a href="https://example.com/a" rel="noopener noreferrer">a</a><a href="https://example.com/b" rel="nofollow ugc sponsored">b</a><a href="https://example.com/c" rel="noopener evil">c</a><a href="https://example.com/d" rel="evil">d</a>|
        )

      assert out =~ ~s|rel="noopener noreferrer"|
      assert out =~ ~s|rel="nofollow ugc sponsored"|

      # the controls: an unknown token goes, and the attribute with it when none is left, the link stays
      assert out =~ ~s|<a href="https://example.com/c" rel="noopener">c</a>|
      assert out =~ ~s|<a href="https://example.com/d">d</a>|
      refute out =~ "evil"
    end

    test "WordPress' chosen image size class" do
      out =
        clean(
          ~s|<img src="https://wp.example.local/a.jpg" alt="" class="size-thumbnail"><img src="https://wp.example.local/b.jpg" alt="" class="size-medium_large wp-image-3"><img src="https://wp.example.local/c.jpg" alt="" class="size-full"><img src="https://wp.example.local/d.jpg" alt="" class="size-huge">|
        )

      assert out =~ ~s|class="size-thumbnail"|
      assert out =~ ~s|class="size-medium_large"|
      assert out =~ ~s|class="size-full"|
      # the control: a size WordPress doesn't name goes, the image stays
      assert out =~ ~s|src="https://wp.example.local/d.jpg"|
      refute out =~ "size-huge"
    end

    test "a code block keeps its language class" do
      assert clean(~s|<pre><code class="language-elixir">IO.puts(1)</code></pre>|) =~
               ~s|<code class="language-elixir">|
    end

    test "our own classes stay, others go, token by token" do
      out = clean(~s|<div class="hidden absolute kg-card"><span class="mention">@a</span></div>|)

      assert out =~ ~s|<div class="kg-card">|
      assert out =~ ~s|<span class="mention">|
      refute out =~ "hidden"
      refute out =~ "absolute"
    end
  end

  describe "removed" do
    # the positive control for each: the element or link around it is still there
    test "scripts and styles, with their content" do
      out =
        clean(
          ~s|<p>Before</p><script>alert(1)</script><style>p{display:none}</style><p>After</p>|
        )

      assert out =~ "<p>Before</p>"
      assert out =~ "<p>After</p>"
      refute out =~ "<script"
      refute out =~ "alert"
      refute out =~ "<style"
    end

    test "event attributes, as on a Ghost bookmark card's thumbnail" do
      out =
        clean(
          ~s|<div class="kg-bookmark-thumbnail"><img src="https://example.com/t.jpg" alt="" onerror="this.style.display = 'none'"></div>|
        )

      assert out =~ ~s|src="https://example.com/t.jpg"|
      refute out =~ "onerror"
    end

    test "style and data attributes" do
      out =
        clean(~s|<div class="kg-card" style="color:red" data-kg-thumbnail="x"><p>Hi</p></div>|)

      assert out =~ ~s|<div class="kg-card">|
      refute out =~ "style="
      refute out =~ "data-"
    end

    test "a form with its inputs and buttons, as in a Ghost signup card" do
      out =
        clean(
          ~s|<div class="kg-card kg-signup-card"><form class="kg-signup-card-form" data-members-form="signup"><input type="email" data-members-email><button type="submit">Subscribe</button></form></div>|
        )

      assert out =~ "kg-signup-card"
      refute out =~ "<form"
      refute out =~ "<input"
      refute out =~ "<button"
    end

    test "svg, iframe, object and embed" do
      out =
        clean(
          ~s|<p>x</p><svg><circle r="1"/></svg><iframe src="https://video.example.com/embed/1"></iframe><object data="https://example.com/a.swf"></object><embed src="https://example.com/a.swf">|
        )

      assert out =~ "<p>x</p>"
      refute out =~ "<svg"
      refute out =~ "<iframe"
      refute out =~ "<object"
      refute out =~ "<embed"
    end

    test "URLs that aren't web addresses" do
      out =
        clean(
          ~s|<a href="javascript:alert(1)">a</a><img src="data:image/png;base64,AAAA" alt="b"><img src="https://example.com/ok.jpg" alt="c" srcset="javascript:alert(1) 1x, https://example.com/ok.jpg 2x">|
        )

      refute out =~ "javascript:"
      refute out =~ "data:image"
      assert out =~ ~s|src="https://example.com/ok.jpg"|
    end
  end
end
