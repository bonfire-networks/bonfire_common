defmodule Bonfire.Common.Text do
  @moduledoc "Helpers for handling plain or rich text (markdown, HTML, etc)"

  use Untangle
  use Arrows
  use Bonfire.Common.E
  alias Bonfire.Common.Extend
  use Bonfire.Common.Config
  use Bonfire.Common.Settings
  alias Bonfire.Common.Media
  alias Bonfire.Common.URIs

  # @add_to_end "..."
  @sentence_seperator " "

  # Regex patterns defined as functions to comply with Erlang/OTP 28
  defp checkbox_regex_unchecked, do: ~r/\s\[\s\]/
  defp checkbox_regex_unchecked_line, do: ~r/\s\[\s\]\s(.*)$/mu
  defp checkbox_regex_checked, do: ~r/\s\[[X,x]\]/
  defp checkbox_regex_checked_line, do: ~r/\s\[[X,x]\]\s(.*)$/mu
  defp checkbox_regex_checkbox_line, do: ~r/^(\s*)[-|<li>]\s\[([ |X|x])\]\s(.*)$/mu
  @checked_box " <input type=\'checkbox\' checked=\'checked\'>"
  @unchecked_box " <input type=\'checkbox\'>"

  @doc """
  Checks if a string is blank.

  ## Examples

      iex> blank?(nil)
      true

      iex> blank?("   ")
      true

      iex> blank?("not blank")
      false
  """
  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """
  def strlen(x) when is_nil(x), do: 0
  def strlen(%{} = obj) when obj == %{}, do: 0
  def strlen(%{}), do: 1
  def strlen(x) when is_binary(x), do: String.length(x)
  def strlen(x) when is_list(x), do: length(x)
  def strlen(x) when x > 0, do: 1
  # let's just say that 0 is nothing
  def strlen(x) when x == 0, do: 0

  @doc """
  Checks if a string contains a substring.

  ## Examples

      iex> contains?("hello world", "world")
      true

      iex> contains?("hello world", "foo")
      false
  """
  def contains?(string, substring)
      when is_binary(string) and is_binary(substring),
      do: string =~ substring

  def contains?(_, _), do: nil

  @doc """
  Splits a string into lines.

  ## Examples

      iex> split_lines("line1\\nline2\\r\\nline3\\rline4")
      ["line1", "line2", "line3", "line4"]
  """
  def split_lines(string) when is_binary(string),
    do: :binary.split(string, ["\r", "\n", "\r\n"], [:global])

  @doc """
  Generates a *random* string of a given length. 

  See also `unique_string/1` and `unique_integer/1`

  ## Examples

      iex> random_string(5) |> String.length()
      5

      > random_string()
      #=> a string of length 10
  """
  def random_string(str_length \\ 10) do
    :crypto.strong_rand_bytes(str_length)
    |> Base.url_encode64()
    |> binary_part(0, str_length)
  end

  @doc """
  Returns the lowercased domain part of an email address, or nil when there isn't one.

  ## Examples

      iex> email_domain("Alice@Example.COM")
      "example.com"

      iex> email_domain("not-an-email")
      nil
  """
  def email_domain(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [_local, domain] when domain != "" -> domain |> String.trim() |> String.downcase()
      _ -> nil
    end
  end

  def email_domain(_), do: nil

  @doc """
  Normalizes a raw domain entry so it matches `email_domain/1` output: trims, drops a leading `@`, downcases.

  ## Examples

      iex> normalize_domain("  @Example.COM ")
      "example.com"
  """
  def normalize_domain(domain) when is_binary(domain) do
    domain |> String.trim() |> String.trim_leading("@") |> String.downcase()
  end

  def normalize_domain(other), do: other

  @doc """
  Generates a *unique* random string.

  "Unique" means that this function will not return the same string more than once on the current BEAM runtime, meaning until the application is next restarted.

  ## Examples

      iex> unique_string()
  """
  def unique_string() do
    unique_integer()
    |> Integer.to_string(16)
  end

  @doc """
  Generates a *unique* random integer.

  "Unique" means that this function will not return the same integer more than once on the current BEAM runtime, meaning until the application is next restarted.

  ## Examples

      iex> unique_integer()
  """
  def unique_integer() do
    System.unique_integer([:positive])
  end

  @doc """
  Hashes the input using a specified algorithm (md5 by default, which is fast but not secure).

  ## Examples

      iex> hash("data", algorithm: :sha256)
      "Om6weQ85rIfJTzhWst0sXREOaBFgImGpqSPTuyOtyLc"

      iex> hash("data")
      "jXd_OF09_siBXSD3SWAm3A"
  """
  def hash(seed, opts \\ []) do
    :crypto.hash(opts[:algorithm] || :md5, seed)
    |> Base.url_encode64(padding: opts[:padding] || false)
  end

  @doc """
  Checks if a string contains HTML tags.

  ## Examples

      iex> contains_html?("<div>Test</div>")
      true

      iex> contains_html?("Just text")
      false

      iex> contains_html?("2 < 3 and 4 > 3")
      false
  """
  # the regex can only match starting from a `<`, so short-circuit on that rather than starting the regex engine (whose `[\s\S]*` is greedy and scans to the end of the string)
  def contains_html?(string),
    do: String.contains?(string, "<") and Regex.match?(html_tag_regex(), string)

  defp html_tag_regex, do: ~r/<\/?[a-z][\s\S]*>/i

  @doc """
  Returns the number of characters changed (insertions plus deletions) between two strings, based on the Myers difference algorithm. Nils are treated as empty strings.

  Note that this measures the magnitude of the change, unlike a signed net length difference (where a same-length replacement would misleadingly count as zero).

  ## Examples

      iex> diff_size("abc", "abc")
      0

      iex> diff_size("abc", "abcde")
      2

      iex> diff_size("abcde", "abc")
      2

      iex> diff_size("abc", "xyz")
      6

      iex> diff_size(nil, "abc")
      3
  """
  def diff_size(previous, current) do
    String.myers_difference(previous || "", current || "")
    |> Enum.map(fn
      {:eq, _} -> 0
      {_ins_or_del, string} -> String.length(string)
    end)
    |> Enum.sum()
  end

  @doc """
  Truncates a string to a maximum length, optionally adding a suffix.

  ## Examples

      iex> truncate("Hello world", 5)
      "Hello"

      iex> truncate("Hello world", 5, "...")
      "He..."

      iex> truncate("Hello world", 7, "...")
      "Hell..."
  """
  def truncate(text, max_length \\ 250, add_to_end \\ nil)

  def truncate(text, max_length, add_to_end) when is_binary(text) do
    text = String.trim(text)

    if String.length(text) < (max_length || 250) do
      text
    else
      if is_binary(add_to_end) do
        length_with_add_to_end = max_length - String.length(add_to_end)
        String.slice(text, 0, length_with_add_to_end) <> add_to_end
      else
        String.slice(text, 0, max_length)
      end
    end
  end

  def truncate(text, _, _), do: text

  @doc """
  Truncates a string to a maximum length, ensuring it ends on a sentence boundary.

  ## Examples

      iex> sentence_truncate("Hello world. This is a test.", 12)
      "Hello world."

      iex> sentence_truncate("Hello world. This is a test.", 12, "...")
      "Hello world...."
  """
  def sentence_truncate(input, length \\ 250, add_to_end \\ "") do
    if(is_binary(input) and String.length(input) > length) do
      "#{do_sentence_truncate(input, length)}#{add_to_end}"
    else
      input
    end
  end

  defp do_sentence_truncate(input, length) do
    length_minus_1 = length - 1

    case input do
      <<result::binary-size(length_minus_1), @sentence_seperator, _::binary>> ->
        # debug("the substring ends with seperator (eg. -)")
        # i. e. "abc-def-ghi", 8 or "abc-def-", 8 -> "abc-def"
        result

      <<result::binary-size(length), @sentence_seperator, _::binary>> ->
        #  debug("the next char after the substring is seperator")
        # i. e. "abc-def-ghi", 7 or "abc-def-", 7 -> "abc-def"
        result

      <<_::binary-size(length)>> ->
        # debug("it is the exact length string")
        # i. e. "abc-def", 7 -> "abc-def"
        input

      _ when length <= 1 ->
        # debug("return an empty string if we reached the beginning of the string")
        ""

      _ ->
        # debug("otherwise look into shorter substring")
        do_sentence_truncate(input, length_minus_1)
    end
  end

  @doc """
  Truncates the input string at the last underscore (`_`) if its length exceeds the given length.
  If the input string is shorter than or equal to the given length, it returns the string as is.

      iex> Bonfire.Common.Text.underscore_truncate("abc_def_ghi", 4)
      "abc"

      iex> Bonfire.Common.Text.underscore_truncate("abc_def_ghi", 10)
      "abc_def"

      iex> Bonfire.Common.Text.underscore_truncate("abc_def_ghi", 5)
      "abc"

      iex> Bonfire.Common.Text.underscore_truncate("abc_def_ghi", 0)
  """
  def underscore_truncate(input, length \\ 250) do
    if(String.length(input) > length) do
      do_underscore_truncate(input, length)
    else
      input
    end
  end

  defp do_underscore_truncate(input, length) do
    length_minus_1 = length - 1

    case input do
      <<result::binary-size(length_minus_1), "_", _::binary>> ->
        # debug("the substring ends with seperator (eg. -)")
        # i. e. "abc-def-ghi", 8 or "abc-def-", 8 -> "abc-def"
        result

      <<result::binary-size(length), "_", _::binary>> ->
        #  debug("the next char after the substring is seperator")
        # i. e. "abc-def-ghi", 7 or "abc-def-", 7 -> "abc-def"
        result

      <<_::binary-size(length)>> ->
        # debug("it is the exact length string")
        # i. e. "abc-def", 7 -> "abc-def"
        input

      _ when length <= 1 ->
        # debug("return an empty string if we reached the beginning of the string")
        ""

      _ ->
        # debug("otherwise look into shorter substring")
        do_underscore_truncate(input, length_minus_1)
    end
  end

  @doc """
  Runs `fun` on the text only if `needle` occurs in it, otherwise returns it untouched.

  Lets a caller keep an expensive rewrite (typically a regex) off the hot path, since `:binary.match/2` is far cheaper than starting the regex engine and most text contains no candidate at all.

  ## Examples

      iex> maybe_replace("hello world", "z", &String.upcase/1)
      "hello world"

      iex> maybe_replace("hello world", "w", &String.upcase/1)
      "HELLO WORLD"
  """
  def maybe_replace(text, needle, fun) when is_binary(text) do
    case :binary.match(text, needle) do
      :nomatch -> text
      _ -> fun.(text)
    end
  end

  def maybe_replace(text, _needle, _fun), do: text

  @doc """
  Undoes the markdown escaping that a WYSIWYG editor's CommonMark serializer applies to bare URLs and `@mentions`.

  Milkdown wraps bare URLs in `<...>` autolinks and escapes a leading `@`, neither of which we want in the stored body.

  ## Examples

      iex> unwrap_markdown_autolinks("see <https://example.com/a> ok")
      "see  https://example.com/a  ok"

      iex> unwrap_markdown_autolinks("hi @<bob@example.com> there")
      "hi  @bob@example.com  there"

      iex> unwrap_markdown_autolinks("escaped \\\\@bob")
      "escaped @bob"

      iex> unwrap_markdown_autolinks("nothing to unwrap here")
      "nothing to unwrap here"
  """
  def unwrap_markdown_autolinks(text) when is_binary(text) do
    text
    |> maybe_replace("<", &unwrap_autolinks/1)
    # for @user@domain.tld
    |> maybe_replace("\\@", &String.replace(&1, "\\@", "@"))
  end

  def unwrap_markdown_autolinks(text), do: text

  @doc ~S"""
  Removes editor-added escapes for ampersands and underscores inside Markdown URLs so link detection can recognise them. Leaves ordinary text and code untouched.

  ## Examples

      iex> normalise_markdown_urls(~S(https://www.youtube.com/watch?v=17MBllYf6OY\&start\_radio=1))
      "https://www.youtube.com/watch?v=17MBllYf6OY&start_radio=1"

      iex> normalise_markdown_urls(~S(keep \_literal\_ and `https://example.com/a\_b`))
      ~S(keep \_literal\_ and `https://example.com/a\_b`)
  """
  def normalise_markdown_urls(text) when is_binary(text) do
    maybe_replace(text, "\\", fn text ->
      # Skip code before matching URLs; unescaping the whole body changes literal Markdown.
      protected =
        ~r/^[ ]{0,3}(`{3,}|~{3,})[^\n]*\n.*?(?:^[ ]{0,3}\1[^\n]*(?:\n|$)|\z)|(`+)[^`]*?\2|^(?: {4}|\t)[^\n]*/ms

      protected
      |> Regex.split(text, include_captures: true, trim: false)
      |> Enum.map_every(2, fn prose ->
        Regex.replace(~r{https?://[^\s<>`"']+}, prose, fn url ->
          String.replace(url, ["\\&", "\\_"], fn
            "\\&" -> "&"
            "\\_" -> "_"
          end)
        end)
      end)
      |> Enum.join()
    end)
  end

  def normalise_markdown_urls(text), do: text

  defp unwrap_autolinks(text) do
    text
    |> Regex.replace(~r/<(http[^>]+)>/, ..., " \\1 ")
    |> Regex.replace(~r/@<([^>]+)>/, ..., " @\\1 ")
  end

  @doc """
  Collapses the backslash-only lines that a WYSIWYG editor's CommonMark serializer emits for visually-blank lines back into real blank lines.

  Milkdown serializes a `hardBreak` node as `\\` + newline, so a blank line entered with Shift+Enter arrives as a backslash-only line. CommonMark reads those as line breaks rather than paragraph breaks, collapsing the whole post into a single paragraph of `<br>`s (bonfire-app#2216, #2218).

  A hard break sitting directly before a blank line is dropped too, since it would otherwise render as a literal `\\` at the end of the paragraph. A hard break between two lines of text is left alone, because there it means what the author intended.

  ## Examples

      iex> normalise_markdown_hard_breaks("first\\n\\\\\\nsecond")
      "first\\n\\nsecond"

      iex> normalise_markdown_hard_breaks("one\\\\\\n\\\\\\ntwo")
      "one\\n\\ntwo"

      iex> normalise_markdown_hard_breaks("roses\\\\\\nviolets")
      "roses\\\\\\nviolets"

      iex> normalise_markdown_hard_breaks("trailing\\\\")
      "trailing"

      iex> normalise_markdown_hard_breaks("no backslashes here")
      "no backslashes here"
  """
  def normalise_markdown_hard_breaks(text) when is_binary(text) do
    maybe_replace(text, "\\", fn text ->
      text
      |> String.split("\n")
      |> Enum.reverse()
      |> Enum.reduce({[], true}, &fix_hard_break_line/2)
      |> elem(0)
      |> Enum.join("\n")
    end)
  end

  def normalise_markdown_hard_breaks(text), do: text

  # Folds right-to-left so each line knows whether the line *after* it ended up blank, which is what decides whether a trailing `\` is a real hard break or a stray one.
  # Seeded `true` so a hard break at end of input counts as one before a blank line, and `String.trim/1` covers space, tab, NBSP and CR in one pass since all carry the Unicode `White_Space` property.
  defp fix_hard_break_line(line, {acc, next_blank?}) do
    {content, cr} =
      if String.ends_with?(line, "\r"),
        do: {binary_part(line, 0, byte_size(line) - 1), "\r"},
        else: {line, ""}

    trimmed = String.trim(content)

    cond do
      # a backslash-only line was meant to be a blank line
      trimmed == "\\" ->
        {[cr | acc], true}

      # a hard break directly before a blank line would render as a literal `\` at paragraph end
      next_blank? and String.ends_with?(trimmed, "\\") ->
        stripped =
          trimmed
          |> binary_part(0, byte_size(trimmed) - 1)
          # else trailing whitespace re-introduces the break we just removed
          |> String.trim_trailing()

        {[stripped <> cr | acc], false}

      true ->
        {[line | acc], trimmed == ""}
    end
  end

  @doc """
  Converts the input content from markdown to HTML if the markdown library is enabled.
  If the content starts with an HTML tag or if the markdown library is not enabled, it skips conversion.

  Pass `hide_trailing_hashtags: true` to mark a last paragraph of only hashtag links `invisible` in the HTML (see `mark_trailing_hashtags/2`), as for a post's body.

      > Bonfire.Common.Text.maybe_markdown_to_html("*Hello World*", [])
      "<p><em>Hello World</em></p>"

      iex> Bonfire.Common.Text.maybe_markdown_to_html("<p>Hello</p>", [])
      "<p>Hello</p>"

      > Bonfire.Common.Text.maybe_markdown_to_html("Not markdown", [])
      "<p>Not markdown</p>"
  """
  # @decorate time_tree(10)
  def maybe_markdown_to_html(content, opts \\ [])

  def maybe_markdown_to_html(nothing, _opts)
      when not is_binary(nothing) or nothing == "" do
    nil
  end

  # def maybe_markdown_to_html("<p>"<>content, opts) do
  #   content
  #   |> String.trim_trailing("</p>")
  #   |> maybe_markdown_to_html(opts) # workaround for weirdness with Earmark's parsing of markdown within html
  # end
  # def maybe_markdown_to_html("<"<>_ = content, opts) do
  #   maybe_markdown_to_html(" "<>content, opts) # workaround for weirdness with Earmark's parsing of html when it starts a line
  # end
  def maybe_markdown_to_html("<" <> _ = content, opts) do
    debug("skipping processing of content that starts with an HTML tag")
    maybe_mark_trailing_hashtags(content, opts)
  end

  def maybe_markdown_to_html(content, opts) do
    {hide_trailing_hashtags?, opts} = Keyword.pop(opts, :hide_trailing_hashtags, false)

    content
    |> do_maybe_markdown_to_html(opts)
    |> maybe_mark_trailing_hashtags(hide_trailing_hashtags: hide_trailing_hashtags?)
  end

  defp maybe_mark_trailing_hashtags(html, opts) do
    if opts[:hide_trailing_hashtags], do: mark_trailing_hashtags(html), else: html
  end

  defp do_maybe_markdown_to_html(content, opts) do
    # debug(content, "input")

    if opts[:markdown_library] == :skip do
      content
    else
      if markdown_library = markdown_library(opts) do
        if opts[:cache] do
          Bonfire.Common.Cache.maybe_apply_cached(
            &markdown_as_html/3,
            [markdown_library, content, opts |> Keyword.drop([:markdown_library, :cache])],
            opts
          )
        else
          markdown_as_html(markdown_library, content, opts)
        end
      else
        error("No markdown library seems to be enabled, skipping processing")
        content
      end
    end
  end

  def markdown_library(opts) do
    initial_library = opts[:markdown_library] || Config.get(:markdown_library, MDEx)

    # initial_library = opts[:markdown_library] || Config.get(:markdown_library, MDEx, name: "Markdown library", type: :radios, options: [MDEx, Earmark, :custom]) 

    cond do
      Extend.module_enabled?(initial_library, opts) ->
        initial_library

      initial_library != MDEx and Extend.module_enabled?(MDEx, opts) ->
        MDEx

      initial_library != Earmark and Extend.module_enabled?(Earmark, opts) ->
        Earmark

      true ->
        nil
    end
  end

  @doc """
  The URLs that stand alone in a top-level paragraph of `markdown`, in order: an image (`![](url)`), a link (`[text](url)`, which is how Linkify stores a bare URL), or a bare URL. This is where media placed in a body sits. A URL in a sentence, a list, a quote or code isn't one.

      > Bonfire.Common.Text.standalone_urls("Intro\\n\\n![](https://example.com/a.png)\\n\\nsee https://example.com/b here")
      ["https://example.com/a.png"]
  """
  def standalone_urls(markdown) when is_binary(markdown) and markdown != "" do
    case parse_markdown_document(markdown, []) do
      {:ok, doc} ->
        for %MDEx.Paragraph{} = paragraph <- doc.nodes,
            {:url, url} <- paragraph_pieces(paragraph, :any),
            do: url

      _ ->
        []
    end
  end

  def standalone_urls(_), do: []

  @doc "The source URL of every image in `body`, in order: `![](url)` anywhere in markdown (not in code), or `<img src>` in HTML (a body that starts with `<`)."
  def image_urls("<" <> _ = html) do
    if Extend.module_enabled?(LazyHTML) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("img[src]")
      |> LazyHTML.attribute("src")
    else
      []
    end
  end

  def image_urls(markdown) when is_binary(markdown) and markdown != "" do
    case parse_markdown_document(markdown, []) do
      {:ok, doc} -> for %MDEx.Image{url: url} <- doc, do: url
      _ -> []
    end
  end

  def image_urls(_), do: []

  @doc """
  Renders `markdown` as `maybe_markdown_to_html/2` does, but cut at each standalone URL (see `standalone_urls/1`) that is in `urls`: `{:html, html}` for each part between, and `{:url, url}` for each cut, in order, so a caller can render a component where each URL sits. The body is parsed once, so a reference link defined in another part still resolves.

  Without such a URL (or for HTML, or with another markdown library) it's one `{:html, html}` part, the same as `maybe_markdown_to_html/2` gives.
  """
  def markdown_parts(markdown, urls, opts \\ [])

  # a body that isn't markdown (a remote post, an import) is cut by `html_parts/3`
  def markdown_parts("<" <> _ = html, urls, opts) do
    if Enum.empty?(urls),
      do: [{:html, maybe_markdown_to_html(html, opts)}],
      else: html_parts(html, urls, opts)
  end

  def markdown_parts(markdown, urls, opts) when is_binary(markdown) and markdown != "" do
    with false <- Enum.empty?(urls),
         false <- String.starts_with?(markdown, "<"),
         MDEx <- markdown_library(opts),
         {:ok, doc} <- parse_markdown_document(markdown, opts),
         pieces = Enum.flat_map(doc.nodes, &node_pieces(&1, urls)),
         true <- Enum.any?(pieces, &match?({:url, _}, &1)) do
      {hide_trailing_hashtags?, opts} = Keyword.pop(opts, :hide_trailing_hashtags, false)

      render_run = fn
        [], parts ->
          parts

        run, parts ->
          [{:html, markdown_as_html(MDEx, %{doc | nodes: Enum.reverse(run)}, opts)} | parts]
      end

      {parts, run} =
        Enum.reduce(pieces, {[], []}, fn
          {:url, url}, {parts, run} -> {[{:url, url} | render_run.(run, parts)], []}
          {:node, node}, {parts, run} -> {parts, [node | run]}
        end)

      case render_run.(run, parts) do
        [{:html, last} | rest] ->
          [
            {:html,
             maybe_mark_trailing_hashtags(last, hide_trailing_hashtags: hide_trailing_hashtags?)}
            | rest
          ]

        parts ->
          parts
      end
      |> Enum.reverse()
    else
      _ -> [{:html, maybe_markdown_to_html(markdown, opts)}]
    end
  end

  def markdown_parts(markdown, _urls, opts), do: [{:html, maybe_markdown_to_html(markdown, opts)}]

  @doc """
  The HTML twin of `markdown_parts/3`, for a body that isn't markdown (a remote post, an import), with the same return: cut at each link or image to a URL in `urls` that is alone in a top-level paragraph (`<p><a href="url">…</a></p>`, whatever the link holds, eg. Mastodon's `<span>`s, or `<p><img src="url"></p>`), or is a bare top-level `<a>` or `<img>` (as an imported embed can leave it). One in a sentence, ending a paragraph, or in a quote or list isn't cut.

  Each part is the body's own HTML, whole elements, as stored; only the last gets `maybe_markdown_to_html/2`'s treatment of an HTML body (hiding trailing hashtags when asked). Without a cut it's one part, as `maybe_markdown_to_html/2` gives. A regex pass, no parse.

      iex> Bonfire.Common.Text.html_parts(~s(<p>a</p><p><a href="https://example.com/v">v</a></p><p>b</p>), ["https://example.com/v"])
      [{:html, "<p>a</p>"}, {:url, "https://example.com/v"}, {:html, "<p>b</p>"}]
  """
  def html_parts(html, urls, opts \\ [])

  def html_parts(html, urls, opts) when is_binary(html) and html != "" do
    {parts, rest} =
      Regex.scan(~r{<a\s[^>]*>.*?</a>|<img\s[^>]*>}s, html, return: :index)
      |> Enum.reduce({[], 0}, fn [{start, length}], {parts, from} ->
        with true <- start >= from,
             url when is_binary(url) <-
               placed_url(binary_part(html, start, length), urls),
             {cut_start, cut_end} <- own_line_range(html, start, start + length),
             true <- cut_start >= from do
          {[{:url, url}, {:html, binary_part(html, from, cut_start - from)} | parts], cut_end}
        else
          _ -> {parts, from}
        end
      end)

    case parts do
      [] ->
        [{:html, maybe_markdown_to_html(html, opts)}]

      parts ->
        last = binary_part(html, rest, byte_size(html) - rest)

        [{:html, maybe_markdown_to_html(last, opts)} | parts]
        |> Enum.reject(&match?({:html, h} when not is_binary(h) or h == "", &1))
        |> Enum.reject(fn
          {:html, h} -> String.trim(h) == ""
          _ -> false
        end)
        |> Enum.reverse()
    end
  end

  def html_parts(html, _urls, opts), do: [{:html, maybe_markdown_to_html(html, opts)}]

  # the URL of a link (`<a href>`) or image (`<img src>`) when it's one of `urls`, compared as the HTML stores it (`&amp;`) or decoded
  defp placed_url(element, urls) do
    with [_, href] <- Regex.run(~r{^<(?:a\s[^>]*?href|img\s[^>]*?src)="([^"]*)"}, element) do
      decoded = HtmlEntities.decode(href)

      cond do
        Enum.member?(urls, decoded) -> decoded
        Enum.member?(urls, href) -> href
        true -> nil
      end
    end
  end

  # where to cut for the link or image from `start` to `stop`: its whole paragraph when it's alone in a top-level `<p>`, itself when it's bare at the top level, else nil
  defp own_line_range(html, start, stop) do
    before = binary_part(html, 0, start)
    after_link = binary_part(html, stop, byte_size(html) - stop)

    with [{p_start, _} | _] <- Regex.run(~r{<p(?:\s[^>]*)?>\s*$}, before, return: :index),
         [{0, close_length}] <- Regex.run(~r{^\s*</p>}, after_link, return: :index),
         true <- top_level?(binary_part(html, 0, p_start)) do
      {p_start, stop + close_length}
    else
      _ -> if top_level?(before), do: {start, stop}
    end
  end

  # whether every block (paragraph, quote, list, code, …) opened in `html` is closed again
  defp top_level?(html) do
    Regex.scan(~r{<(/?)(p|blockquote|li|ul|ol|pre|div|figure|table|details)\b}i, html,
      capture: :all_but_first
    )
    |> Enum.reduce(0, fn
      ["/", _], depth -> depth - 1
      [_, _], depth -> depth + 1
    end)
    |> Kernel.<=(0)
  end

  @doc """
  `markdown` with each URL that ends a line of a top-level paragraph (see `standalone_urls/1`: alone on its line, after a label, or ending the paragraph) moved to a paragraph of its own, and any lines after it to another, so it's alone in its paragraph once rendered to HTML, eg. for another instance to place its media (see `html_parts/3`). Only blank lines are inserted, where the URL starts and where its line ends, in place of the spaces before the URL (which would otherwise trail the line before it): nothing else the author typed is rewritten. One parse.
  """
  def own_paragraph_urls(markdown) when is_binary(markdown) and markdown != "" do
    with {:ok, doc} <- parse_markdown_document(markdown, []) do
      line_starts =
        [0 | for({at, _} <- :binary.matches(markdown, "\n"), do: at + 1)] |> List.to_tuple()

      doc.nodes
      |> Enum.flat_map(&own_paragraph_inserts(&1, markdown, line_starts))
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.reduce(markdown, fn {from, to, insert}, markdown ->
        binary_part(markdown, 0, from) <>
          insert <>
          binary_part(markdown, to, byte_size(markdown) - to)
      end)
    else
      _ -> markdown
    end
  end

  def own_paragraph_urls(markdown), do: markdown

  # `{from, to, text}` for each URL in `paragraph` that ends a line, as `paragraph_pieces/2` cuts it: the text replaces the bytes from `from` to `to` (none, or the spaces before the URL)
  defp own_paragraph_inserts(%MDEx.Paragraph{nodes: nodes}, markdown, line_starts) do
    lines =
      Enum.chunk_while(
        nodes,
        [],
        fn
          %{__struct__: break} = node, line when break in [MDEx.SoftBreak, MDEx.LineBreak] ->
            {:cont, Enum.reverse([node | line]), []}

          node, line ->
            {:cont, [node | line]}
        end,
        fn
          [] -> {:cont, []}
          line -> {:cont, Enum.reverse(line), []}
        end
      )

    last = length(lines) - 1

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      with {before, url} <- line_end_media(line, :any),
           %{sourcepos: %{start: {line_no, column}, end: {end_line, end_column}}} = node <-
             line_end_node(line),
           true <- bare_url_node?(node),
           at when is_integer(at) <-
             url_offset(
               node,
               url,
               markdown,
               line_starts,
               {line_no, column},
               {end_line, end_column}
             ),
           true <- word_start?(markdown, at) do
        before_insert =
          if index > 0 or not blank_inline?(before),
            do: [{at - spaces_before(markdown, at), at, "\n\n"}],
            else: []

        after_insert =
          if index < last and end_line < tuple_size(line_starts),
            do: [{elem(line_starts, end_line) - 1, elem(line_starts, end_line) - 1, "\n"}],
            else: []

        before_insert ++ after_insert
      else
        _ -> []
      end
    end)
  end

  defp own_paragraph_inserts(_node, _markdown, _line_starts), do: []

  # whether byte `at` of `markdown` starts a word: a URL glued to the text before it (eg. inside a broken link) isn't moved
  defp word_start?(_markdown, 0), do: true
  defp word_start?(markdown, at), do: :binary.at(markdown, at - 1) in [?\s, ?\t, ?\n]

  # how many spaces or tabs come right before byte `at` of `markdown`, on its line
  defp spaces_before(markdown, at, count \\ 0)

  defp spaces_before(markdown, at, count) when at > 0 do
    case :binary.at(markdown, at - 1) do
      char when char in [?\s, ?\t] -> spaces_before(markdown, at - 1, count + 1)
      _ -> count
    end
  end

  defp spaces_before(_markdown, _at, count), do: count

  # only a bare URL moves (as typed, or as Linkify writes it): a named link, a mention or a hashtag ending a line stays where it is
  defp bare_url_node?(%MDEx.Text{}), do: true

  # a link whose text is the start of its URL without the scheme (`[video.example.com/w/x](https://video.example.com/w/x)`, maybe shortened): `url_text?/1` would also take a mention (`[@someone](https://example.com/@someone)`)
  defp bare_url_node?(%MDEx.Link{url: url, nodes: [%MDEx.Text{literal: text}]}) do
    shown =
      text
      |> String.trim()
      |> String.trim_trailing("...")
      |> String.trim_trailing("…")
      |> String.replace(~r{^(https?://)?(www\.)?}, "")

    shown != "" and String.starts_with?(String.replace(url, ~r{^https?://(www\.)?}, ""), shown)
  end

  defp bare_url_node?(_), do: false

  # the node that ends `line`: the media `line_end_media/2` found there
  defp line_end_node(line) do
    case line |> trim_trailing_inline() |> Enum.reverse() do
      [%MDEx.Text{literal: literal} = text | rest] ->
        if String.replace(literal, end_punctuation_regex(), "") == "",
          do: List.first(rest),
          else: text

      [node | _] ->
        node

      _ ->
        nil
    end
  end

  # where the URL starts in `markdown`: where its link or image starts, or where it sits in a text node
  defp url_offset(
         %MDEx.Text{},
         url,
         markdown,
         line_starts,
         {line_no, column},
         {end_line, end_column}
       ) do
    from = elem(line_starts, line_no - 1) + column - 1
    to = elem(line_starts, end_line - 1) + end_column

    case :binary.matches(binary_part(markdown, from, to - from), url) do
      [] -> nil
      matches -> from + (matches |> List.last() |> elem(0))
    end
  end

  defp url_offset(_node, _url, _markdown, line_starts, {line_no, column}, _end),
    do: elem(line_starts, line_no - 1) + column - 1

  # a top-level node as pieces: `{:node, node}` to render, `{:url, url}` where the body places media. Only a paragraph can hold a cut: a list, a quote or code never does
  defp node_pieces(%MDEx.Paragraph{} = paragraph, urls) do
    for piece <- paragraph_pieces(paragraph, urls) do
      case piece do
        {:url, url} -> {:url, url}
        {:nodes, nodes} -> {:node, %{paragraph | nodes: nodes}}
      end
    end
  end

  defp node_pieces(node, _urls), do: [{:node, node}]

  # A paragraph cut at each media URL (in `urls`, or any with `:any`) that ends a line: alone on its line, or after a label ("Blog post: https://…"). The text before the URL stays, as its own paragraph. The URL's own text is dropped (the media shows it) unless it's a named link ("[the post](url)"). A URL in the middle of a line isn't cut.
  defp paragraph_pieces(%MDEx.Paragraph{nodes: nodes}, urls) do
    nodes
    |> Enum.chunk_while(
      [],
      fn
        %{__struct__: break} = node, line when break in [MDEx.SoftBreak, MDEx.LineBreak] ->
          {:cont, {Enum.reverse(line), node}, []}

        node, line ->
          {:cont, [node | line]}
      end,
      fn
        [] -> {:cont, []}
        line -> {:cont, {Enum.reverse(line), nil}, []}
      end
    )
    |> Enum.flat_map(fn {line, break} ->
      case line_end_media(line, urls) do
        {before, url} -> [{:nodes, before}, {:url, url}]
        nil -> [{:nodes, line ++ List.wrap(break)}]
      end
    end)
    |> Enum.chunk_by(&match?({:url, _}, &1))
    |> Enum.flat_map(fn
      [{:url, _} | _] = urls ->
        urls

      runs ->
        [
          {:nodes,
           runs |> Enum.flat_map(fn {:nodes, nodes} -> nodes end) |> trim_trailing_inline()}
        ]
    end)
    |> Enum.reject(fn
      {:nodes, nodes} -> blank_inline?(nodes)
      _ -> false
    end)
  end

  # `{nodes before, url}` when `line` ends with media whose URL is in `urls`, else nil
  defp line_end_media(line, urls) do
    case line |> trim_trailing_inline() |> Enum.reverse() |> drop_end_punctuation() do
      [%MDEx.Image{url: url} | before] ->
        cut_line(before, [], url, urls)

      [%MDEx.Link{url: url} = link | before] ->
        cut_line(before, if(url_text?(link), do: [], else: [link]), url, urls)

      [%MDEx.Text{literal: literal} | before] ->
        case Regex.run(~r/^(.*?)(https?:\/\/\S*[^\s.,;:!?)])$/s, literal, capture: :all_but_first) do
          [text, url] ->
            cut_line(
              before,
              if(String.trim(text) == "", do: [], else: [%MDEx.Text{literal: text}]),
              url,
              urls
            )

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # the punctuation that ends a sentence after a URL (`https://x.`, `[x](u).`, `(see https://x)`) isn't part of it: dropped, as the cut ends the line there a function rather than a module attribute: a compiled regex can't be stored in one on Erlang/OTP 28
  defp end_punctuation_regex, do: ~r/[.,;:!?)]+$/

  defp drop_end_punctuation([%MDEx.Text{literal: literal} = text | rest] = reversed) do
    case String.replace(literal, end_punctuation_regex(), "") do
      ^literal -> reversed
      "" -> rest
      trimmed -> [%{text | literal: trimmed} | rest]
    end
  end

  defp drop_end_punctuation(reversed), do: reversed

  defp cut_line(reversed_before, kept, url, urls) do
    if urls == :any or Enum.member?(urls, url),
      do: {trim_trailing_inline(Enum.reverse(reversed_before) ++ kept), url}
  end

  # a link whose text is its URL, as Linkify writes a bare URL (shortened, without its scheme)
  defp url_text?(%MDEx.Link{url: url, nodes: [%MDEx.Text{literal: text}]}) do
    text = text |> String.trim() |> String.trim_trailing("...")
    not String.contains?(text, " ") and String.contains?(url, text)
  end

  defp url_text?(_), do: false

  # without the whitespace (and line breaks) at the end of a line
  defp trim_trailing_inline(nodes) do
    case Enum.reverse(nodes) do
      [%{__struct__: break} | rest] when break in [MDEx.SoftBreak, MDEx.LineBreak] ->
        trim_trailing_inline(Enum.reverse(rest))

      [%MDEx.Text{literal: literal} = text | rest] ->
        case String.trim_trailing(literal) do
          "" -> trim_trailing_inline(Enum.reverse(rest))
          trimmed -> Enum.reverse([%{text | literal: trimmed} | rest])
        end

      _ ->
        nodes
    end
  end

  defp blank_inline?(nodes), do: trim_trailing_inline(nodes) == []

  defp parse_markdown_document(markdown, opts) do
    if Extend.module_enabled?(MDEx),
      do: MDEx.parse_document(markdown, mdex_options(opts)),
      else: {:error, :no_mdex}
  end

  # `content` is markdown, or an `MDEx.Document` (see `markdown_parts/3`)
  defp markdown_as_html(MDEx, content, opts) do
    case MDEx.to_html(content, mdex_options(opts)) do
      {:ok, html} ->
        html

      e ->
        error(e)
        if is_binary(content), do: content, else: ""
    end
  end

  defp markdown_as_html(Earmark = processor, content, opts) do
    do_earmark_as_html(processor, content, opts)
  end

  # the options for MDEx, shared by rendering and by `parse_markdown_document/2`, so a body rendered in parts renders as it would whole
  defp mdex_options(opts) do
    {sanitize?, opts} = Keyword.pop(opts, :sanitize, true)

    [
      parse: [
        smart: false,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true
      ],
      extension: [
        strikethrough: true,
        tasklist: true,
        # can't use because things @ mentions are emails
        autolink: false,
        table: true,
        tagfilter: true,
        header_id_prefix: ""
        #  shortcodes: true # NOTE: not needed because we use smile lib
      ],
      render: [
        hardbreaks: true,
        # unsafe_: opts[:__unsafe__],
        # Allow rendering of raw HTML and potentially dangerous links?
        unsafe_: opts[:__unsafe__] || sanitize? != false,
        # Escape raw HTML instead of clobbering it.
        escape: sanitize? == false and !opts[:__unsafe__]
      ],
      sanitize:
        cond do
          is_list(sanitize?) ->
            sanitize?

          sanitize? ->
            [
              # nil preserves Linkify-generated rel (tag ugc / nofollow noopener ugc);
              # ammonia forbids rel in generic_attributes so we allow it per-tag on <a> below
              link_rel: Keyword.get(opts, :link_rel, nil),
              # only the `data-` attributes our own markup uses: any other would let a post reach the hooks of our scripts
              generic_attributes:
                ["data-tag", "data-user", "data-emoji", "data-line"] ++
                  Keyword.get(opts, :generic_attributes, []),
              # only the classes our own markup uses, per tag (see `sanitizer_classes/0`): any other class would let a post use our styles
              allowed_classes: sanitizer_classes(),
              add_tag_attributes:
                Map.merge(
                  %{"a" => ["rel"]},
                  Keyword.get(opts, :add_tag_attributes, %{})
                ),
              url_schemes: [
                "ftp",
                "ftps",
                "geo",
                "http",
                "https",
                "irc",
                "ircs",
                "magnet",
                "mailto",
                "news",
                "nntp",
                "openpgp4fpr",
                "sip",
                "sms",
                "smsto",
                "tel",
                "url",
                "webcal",
                "wtai",
                "xmpp"
              ],
              url_relative:
                case opts[:url_base] do
                  false -> :deny
                  nil -> :passthrough
                  url_base -> {:rewrite_with_base, url_base}
                end
            ]

          true ->
            nil
        end,
      # sanitizes the HTML (but keeping things we need, like class and attributes), default is usually `MDEx.default_sanitize_options()` 

      #  NOTE: unsafe_ should be set to true so the sanitizer is given raw HTML to sanitize
      # classes rather than inline styles (which the sanitizer strips), coloured per theme by `Bonfire.UI.Common.CodeTheme`
      syntax_highlight: [
        engine: :lumis,
        formatter: :html_linked
      ]
    ]

    # |> Keyword.merge(opts)
    #  |> debug("md_opts")
  end

  defp do_earmark_as_html(processor, content, opts) do
    case [
           # inner_html: true,
           escape: false,
           breaks: true,
           smartypants: false,
           registered_processors: [
             # {"a", &md_add_target/1},
             {"h1", &md_heading_anchors/1},
             {"h2", &md_heading_anchors/1},
             {"h3", &md_heading_anchors/1},
             {"h4", &md_heading_anchors/1},
             {"h5", &md_heading_anchors/1},
             {"h6", &md_heading_anchors/1}
           ]
         ]
         |> Keyword.merge(
           Keyword.take(opts, [
             :all,
             :annotations,
             :breaks,
             :code_class_prefix,
             :file,
             :footnote_offset,
             :footnotes,
             :gfm,
             :gfm_tables,
             :line,
             :math,
             :messages,
             :parse_inline,
             :pedantic,
             :pure_links,
             :renderer,
             :smartypants,
             :sub_sup,
             :timeout,
             :wikilinks,
             :inner_html,
             :registered_processors
           ])
         )
         |> processor.as_html(content, ...) do
      {:ok, html, _} ->
        markdown_checkboxes(html)
        |> debug("MD output for: #{content}")

      {:ok, html} ->
        markdown_checkboxes(html)
        |> debug("MD output for: #{content}")

      e ->
        error(e)
        nil
    end
  end

  @doc """
  Replaces each code span and code block in Markdown with an opaque token, so that processing meant for prose (sanitizing, mentions and hashtags, emoji, link rewriting...) can't alter code. Returns the masked text and a function that puts the original code back.

      iex> {masked, unmask} = mask_markdown_code("say `a < \\"b\\"` @you")
      iex> masked =~ "`"
      false
      iex> unmask.(masked)
      "say `a < \\"b\\"` @you"
  """
  def mask_markdown_code(markdown) when is_binary(markdown) and markdown != "" do
    # only parse when something could start code: backticks, `~~~` fences, or 4-space/tab indentation
    if String.contains?(markdown, ["`", "~~~", "    ", "\t"]),
      do: do_mask_markdown_code(markdown),
      else: {markdown, & &1}
  end

  def mask_markdown_code(other), do: {other, & &1}

  @doc """
  Like `mask_markdown_code/1`, for images (`![alt](url)`): their URL must reach the stored body as written, so it can still be matched to its media, rather than be turned into a link or a local path by processing meant for prose.

      iex> {masked, unmask} = mask_markdown_images("see ![](https://example.com/a.png) here")
      iex> masked =~ "example.com"
      false
      iex> unmask.(masked)
      "see ![](https://example.com/a.png) here"
  """
  def mask_markdown_images(markdown) when is_binary(markdown) and markdown != "" do
    if String.contains?(markdown, "!["),
      do:
        mask_markdown_ranges(markdown, markdown_node_ranges(markdown, &match?(%MDEx.Image{}, &1))),
      else: {markdown, & &1}
  end

  def mask_markdown_images(other), do: {other, & &1}

  defp do_mask_markdown_code(markdown) do
    mask_markdown_ranges(markdown, markdown_code_ranges(markdown))
  end

  # swaps each byte range `{from, to}` of `markdown` for an opaque token, returning the masked text and a function that puts the originals back
  defp mask_markdown_ranges(markdown, ranges) do
    case ranges do
      [] ->
        {markdown, & &1}

      ranges ->
        prefix = "bfmask#{System.unique_integer([:positive])}x"

        # replace from the end so earlier byte offsets stay valid
        {masked, codes} =
          ranges
          |> Enum.sort(:desc)
          |> Enum.with_index()
          |> Enum.reduce({markdown, %{}}, fn {{from, to}, i}, {text, codes} ->
            token = "#{prefix}#{i}x"
            <<before::binary-size(from), code::binary-size(to - from), rest::binary>> = text
            {before <> token <> rest, Map.put(codes, token, code)}
          end)

        tokens = Map.keys(codes)

        {masked,
         fn
           text when is_binary(text) -> String.replace(text, tokens, &Map.fetch!(codes, &1))
           other -> other
         end}
    end
  end

  # Byte ranges `{from, to}` of code in Markdown: inline spans including their backticks, and code blocks as whole lines (so fences, indentation and any `> ` or list prefix are included).
  defp markdown_code_ranges(markdown) do
    markdown_node_ranges(markdown, &(match?(%MDEx.Code{}, &1) or match?(%MDEx.CodeBlock{}, &1)))
  end

  # Byte ranges `{from, to}` of the Markdown nodes `keep?` picks: a code block as whole lines, any other node (an inline one, such as code or an image) from its first to its last character.
  defp markdown_node_ranges(markdown, keep?) do
    with true <- Extend.module_enabled?(MDEx),
         {:ok, doc} <- MDEx.parse_document(markdown) do
      line_starts =
        [0 | for({pos, _} <- :binary.matches(markdown, "\n"), do: pos + 1)]
        |> List.to_tuple()

      line_start = fn line -> elem(line_starts, line - 1) end

      line_end = fn line ->
        if line < tuple_size(line_starts),
          do: elem(line_starts, line) - 1,
          else: byte_size(markdown)
      end

      for node <- doc, keep?.(node) do
        %{start: {start_line, start_col}, end: {end_line, end_col}} = node.sourcepos

        case node do
          %MDEx.CodeBlock{} ->
            # an end column of 0 means the block ended with the previous line
            {line_start.(start_line),
             line_end.(if end_col == 0, do: end_line - 1, else: end_line)}

          _inline ->
            {line_start.(start_line) + start_col - 1, line_start.(end_line) + end_col}
        end
      end
    else
      e ->
        warn(
          e,
          "Could not parse markdown, so its code and images won't be protected from processing"
        )

        []
    end
  end

  # This will only be applied to nodes as it will become a TagSpecificProcessors
  # defp md_add_target(node) do
  #   # debug(node)
  #   if Regex.match?(
  #        ~r{\.x\.com\z},
  #        Earmark.AstTools.find_att_in_node(node, "href", "")
  #      ),
  #      do: Earmark.AstTools.merge_atts_in_node(node, target: "_blank"),
  #      else: node
  # end

  defp md_heading_anchors({tag, _attrs, text, extra} = _node) do
    # node
    # |> debug()
    {tag,
     [
       {"id", slug(text)}
     ], text, extra}
  end

  @doc """
  Generates a URL-friendly slug from the given text.
  The text is downcased, trimmed, spaces are replaced with dashes, and it is URI-encoded.

      iex> Bonfire.Common.Text.slug("Hello World!")
      "hello-world"

      iex> Bonfire.Common.Text.slug("Elixir Programming")
      "elixir-programming"

      iex> Bonfire.Common.Text.slug("Special & Characters")
      "special-characters"

      iex> Bonfire.Common.Text.slug(["Many", nil, ["Words"]])
      "many-words"
  """
  def slug(text, opts \\ [])
  def slug({_tag, _attrs, text, _extra}, opts), do: slug(text, opts)

  def slug(text, opts) when is_list(text),
    do:
      text
      |> Enum.filter(&(not is_nil(&1) and &1 != ""))
      |> Enum.flat_map(&md_tag_text/1)
      |> List.flatten()
      |> Enum.join(opts[:joiner] || "-")
      |> slug(opts)

  def slug(text, opts) do
    truncate = opts[:truncate]

    text
    |> String.trim()
    # |> String.downcase()
    # |> String.replace(~r/\s+/, opts[:joiner] || "-")
    |> String.replace(
      ["/", "-", "+", ":", "@", "%", "*", ",", ".", "|", "(", ")", "&", "!"],
      opts[:joiner] || "-"
    )
    |> SimpleSlug.slugify(
      joiner: opts[:joiner] || "-",
      lowercase?: opts[:lowercase?] != false,
      truncate:
        cond do
          truncate == false -> false
          is_integer(truncate) -> truncate
          true -> 128
        end
    )
    |> URI.encode()
  end

  @doc """
  Converts input to snake_case.

  ## Examples

      iex> maybe_to_snake("CamelCase")
      "camel_case"
  """
  def maybe_to_snake(string), do: Recase.to_snake("#{string}")

  defp md_tag_text({_tag, _attrs, text, _extra}), do: md_tag_text(text)
  defp md_tag_text(text) when is_binary(text), do: [text]
  defp md_tag_text(texts) when is_list(texts), do: texts
  defp md_tag_text(_), do: []

  @sanitizer_classes_key {__MODULE__, :sanitizer_classes}
  @sanitizer_classes_default_themes %{"light" => "bamboo_light", "dark" => "bamboo_vulgaris"}

  @doc """
  The CSS classes the HTML sanitiser keeps, per tag (ammonia's `allowed_classes` takes exact names, no wildcards): the classes our own markup uses (mentions, hashtags, emoji), and the ones the code highlighter emits.

  The highlighter's lists are generated from Lumis rather than kept by hand: `language-*` from every language id and alias Lumis knows, and `l-*` from the highlight scopes of the code themes in use (scope `keyword.function` becomes class `l-keyword-function`), plus `l-line` and `l-line-number`. Built on first use and cached in `:persistent_term`, so a sanitise call only reads it.
  """
  def sanitizer_classes do
    case :persistent_term.get(@sanitizer_classes_key, nil) do
      nil ->
        classes = build_sanitizer_classes()
        :persistent_term.put(@sanitizer_classes_key, classes)
        classes

      classes ->
        classes
    end
  end

  defp build_sanitizer_classes do
    own = ["hashtag", "mention", "u-url", "h-card", "invisible", "ellipsis"]

    {code_langs, code_tokens} =
      if Extend.module_enabled?(Lumis),
        do: {lumis_language_classes(), lumis_token_classes()},
        else: {[], []}

    %{
      "a" => own,
      "p" => own,
      "div" => own,
      "span" => own ++ code_tokens,
      "img" => ["emoji"],
      "pre" => ["lumis", "highlight"],
      "code" => code_langs
    }
  end

  defp lumis_language_classes do
    Lumis.Languages.available()
    |> Enum.flat_map(&[&1.id | &1.aliases])
    |> Enum.uniq()
    |> Enum.map(&"language-#{&1}")
  end

  defp lumis_token_classes do
    themes = Config.get([:ui, :code_themes], @sanitizer_classes_default_themes)

    scopes =
      (Map.values(@sanitizer_classes_default_themes) ++ Map.values(themes))
      |> Enum.uniq()
      |> Enum.flat_map(fn name ->
        case Lumis.Theme.get(name) do
          %{highlights: highlights} -> Map.keys(highlights)
          _ -> []
        end
      end)

    (["l-line", "l-line-number"] ++ Enum.map(scopes, &("l-" <> String.replace(&1, ".", "-"))))
    |> Enum.uniq()
  end

  @doc """
  Highlights a source file with Lumis (language detected from the filename), using the same classes as markdown code blocks so it's coloured per theme by `Bonfire.UI.Common.CodeTheme`. Falls back to Phoenix.HTML if Lumis isn't available.

  `opts` are extra options for the Lumis `:html_linked` formatter, e.g. `line_numbers: true` or `structure: :inline`. With `line_numbers: true` each line also gets an `id="L<n>"` and its number becomes a `#L<n>` link, so lines can be linked to and styled with `:target` without JS.

  ## Examples

      > code_syntax("defmodule Test do end", "test.ex")
      #=> "<pre class=\"lumis highlight\"><code class=\"language-elixir\" ...><span class=\"l-keyword-function\">defmodule</span> ..."
  """
  def code_syntax(text, filename, opts \\ []) do
    if Extend.module_enabled?(Lumis) do
      Lumis.highlight!(text,
        formatter:
          {:html_linked,
           Keyword.merge([language: code_language(filename), pre_class: "highlight"], opts)}
      )
      |> maybe_anchor_code_lines(opts[:line_numbers])
    else
      Phoenix.HTML.Tag.content_tag(:pre, Phoenix.HTML.Tag.content_tag(:code, text),
        class: "highlight"
      )
    end
  end

  # Lumis guesses the language from the filename, but extensions' `deps.hex`, `deps.git` and `deps.path` are TOML under extensions it doesn't know
  defp code_language(filename) when is_binary(filename) do
    if Path.basename(filename) in ["deps.hex", "deps.git", "deps.path"],
      do: "toml",
      else: filename
  end

  defp code_language(filename), do: filename

  # Lumis only marks lines with `data-line`, so add the `id` that `#L<n>` links and `:target` need, and turn each line number into such a link
  defp maybe_anchor_code_lines(html, true) do
    html
    |> String.replace(
      ~r/<span class="l-line([^"]*)" data-line="(\d+)">/,
      ~s(<span id="L\\2" class="l-line\\1" data-line="\\2">)
    )
    |> String.replace(
      ~r/<span class="(l-line-number[^"]*)" aria-hidden="true">(\d+)<\/span>/,
      ~s(<a href="#L\\2" class="\\1" aria-hidden="true" tabindex="-1">\\2</a>)
    )
  end

  defp maybe_anchor_code_lines(html, _), do: html

  @doc """
  Sanitizes HTML content to ensure it is safe.

  It is recommended to call this before storing any that data is coming in from the user or from a remote instance

  Uses HtmlSanitizeEx if enabled, otherwise returns input.

  ## Examples

      iex> Bonfire.Common.Text.maybe_sane_html("<script>alert('XSS')</script>")
      "alert('XSS')"

      iex> Bonfire.Common.Text.maybe_sane_html("<p>Safe</p>")
      "<p>Safe</p>"

      iex> Bonfire.Common.Text.maybe_sane_html("<div class='test'>Safe</div>")
      "Safe"

      iex> Bonfire.Common.Text.maybe_sane_html("<div class='invisible'>Safe</div>")
      "<div class=\\"invisible\\">Safe</div>"

      iex> Bonfire.Common.Text.maybe_sane_html("<span class='invisible'>Safe</span>")
      "<span class=\\"invisible\\">Safe</span>"
  """
  def maybe_sane_html(content) when is_binary(content) do
    # TODO: can we use MDEx's sanitizer here when dealing with markdown content, and LazyHTML for raw HTML content?
    if Extend.module_enabled?(Bonfire.Common.Text.SanitizeHTML) do
      Bonfire.Common.Text.SanitizeHTML.sanitize(content)
    else
      # no sanitiser: the text is escaped, never passed on as HTML
      escape_html(content) || content
    end
  end

  def maybe_sane_html(content) do
    warn(content, "not a string")
    nil
  end

  @doc """
  As `maybe_sane_html/1`, with the sanitising an import source's admin chose for its articles' bodies:

  - `:imported`: keeps more of an imported article's structure (see `Bonfire.Common.Text.SanitizeImportedHTML`), still without anything that could run;
  - `:unsafe`: the HTML as it came, for a source whose authors are trusted (whoever can write raw HTML there could then run script here);
  - anything else (`:strict`, nil): `maybe_sane_html/1`.
  """
  def maybe_sane_html(content, :imported) when is_binary(content) do
    if Extend.module_enabled?(Bonfire.Common.Text.SanitizeImportedHTML) do
      Bonfire.Common.Text.SanitizeImportedHTML.sanitize(content)
    else
      maybe_sane_html(content)
    end
  end

  def maybe_sane_html(content, :unsafe) when is_binary(content), do: content
  def maybe_sane_html(content, _kind), do: maybe_sane_html(content)

  @doc """
  Extracts plain text from HTML content.

  ## Examples

      iex> text_only("<div>Text</div>")
      "Text"

      iex> text_only({:safe, "<div>Safe Text</div>"})
      "Safe Text"
  """
  def text_only({:safe, content}), do: text_only(content)

  def text_only(%LazyHTML{} = content) do
    LazyHTML.text(content)
  end

  def text_only(content) when is_binary(content) do
    if Extend.module_enabled?(HtmlSanitizeEx) do
      HtmlSanitizeEx.strip_tags(content)
    else
      content
      |> escape_html()
    end
  end

  def text_only(_content), do: nil

  @doc """
  Renders markdown (HTML stays as it is) and then takes the markup out, for a text shown clamped to a line or two, so `**bold**` reads "bold" and a link reads as its text. The text comes back unescaped, as a template escapes it.

      iex> markdown_to_text("We read **slowly**, see [our list](https://example.local/list)")
      "We read slowly, see our list"

      iex> markdown_to_text("<p>Fish &amp; chips</p>")
      "Fish & chips"

      iex> markdown_to_text(nil)
      nil
  """
  def markdown_to_text(content) do
    case maybe_markdown_to_html(content) do
      # parsed rather than stripped with `text_only/1` on the string, which leaves entities such as `&amp;` for the template to escape again
      html when is_binary(html) -> html |> as_lazy_html() |> text_only() |> String.trim()
      _ -> nil
    end
  end

  @doc """
  Escapes text for putting into HTML, so it shows as written: unlike `text_only/1`, which takes HTML out, this keeps the text and makes it safe to show.

      iex> escape_html("Only <b>members</b> & friends")
      "Only &lt;b&gt;members&lt;/b&gt; &amp; friends"

      iex> escape_html(:ok)
      "ok"
  """
  def escape_html(nil), do: nil

  def escape_html(""), do: nil

  def escape_html(text) when is_binary(text),
    do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  def escape_html(text),
    do: text |> to_string() |> escape_html()

  @doc """
  Collapses any run of whitespace (incl. newlines/tabs) into a single space and trims.

  ## Examples

      iex> normalize_whitespace("  hello\\n  world\\t! ")
      "hello world !"
  """
  def normalize_whitespace(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_whitespace(text), do: text

  @doc """
  Converts text to emotes if the Emote module is enabled.

  ## Examples

      iex> maybe_emote(":smile:", nil, [])
      "😄"
  """
  def maybe_emote(content, user \\ nil, opts \\ []) do
    if Extend.module_enabled?(Emote, user) do
      # debug(custom_emoji)

      if opts[:parse_custom_emoji] != false do
        Emote.convert_text(content,
          custom_fn: fn text -> maybe_other_custom_emoji(text, user) end,
          custom_emoji: opts[:emoji] || []
        )
      else
        Emote.convert_text(content)
      end

      # |> debug()
    else
      content
    end
  end

  defp maybe_other_custom_emoji(text, user) do
    # debug(user)
    #  |> debug()
    case text
         # |> String.trim()
         # TEMP workaround for messed up markdown coming from composer 
         |> String.replace("\\_", "_")
         |> String.split(":") do
      ["", _icon, ""] ->
        case Settings.get([:custom_emoji, text], nil, user) do
          nil ->
            text

          emoji ->
            label = e(emoji, :label, nil) || text

            case emoji_src(e(emoji, :url, nil) || Media.emoji_url(emoji)) do
              nil ->
                text

              src ->
                " <img alt='#{escape_attr(label)}' title='#{escape_attr(label)}' class='emoji' data-emoji='#{escape_attr(text)}' src='#{escape_attr(src)}' /> "
            end
        end

      ["", family, icon, ""] ->
        " <img alt='#{escape_attr(text)}' title='#{escape_attr(text)}' class='emoji' src='#{escape_attr("https://api.iconify.design/#{family}/#{icon}.svg")}' /> "

      #     "<span iconify='#{family}:#{icon}' class='iconify' aria-hidden='true'>
      #   <img class='hidden' alt='#{text}' title='#{text}' src='https://api.iconify.design/#{family}/#{icon}.svg' onerror=\"this.src='https://api.iconify.design/ooui/article-not-found-ltr.svg'\" />
      # </span>"
      _ ->
        text
    end
  end

  # Emoji images are built as markup after sanitising, so every value placed in an attribute is escaped and `src` is limited to an http(s) address or a local path.
  defp escape_attr(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp emoji_src("//" <> _), do: nil
  defp emoji_src("/" <> _ = path), do: path

  defp emoji_src(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        url

      _ ->
        nil
    end
  end

  defp emoji_src(_), do: nil

  @doc """
  Replaces the href attribute of <a> tags in HTML input using a replacements map.

  Accepts a string, tree, or LazyHTML struct as input.
  Returns the updated tree.

  ## Examples

    iex> Bonfire.Common.Text.replace_links("<a href='/foo'>test</a>", %{"/foo" => "/bar"})
    [{"a", [{"href", "/bar"}], ["test"]}]

    iex> Bonfire.Common.Text.replace_links([{"a", [{"href", "/foo"}], ["test"]}], %{"/foo" => "/bar"})
    [{"a", [{"href", "/bar"}], ["test"]}]

    iex> Bonfire.Common.Text.replace_links("<a href='/foo'>test</a>", %{"/baz" => "/qux"})
    [{"a", [{"href", "/foo"}], ["test"]}]
  """
  def replace_links(input, replacements_map, fallback_match_fn \\ nil, opts \\ [])

  def replace_links(nil, _, _, _), do: nil

  def replace_links(input, replacements_map, fallback_match_fn, opts) do
    # `base:` resolves relative hrefs against it (eg. a remote object's URL) in the same walk
    base = opts[:base]

    if (is_map(replacements_map) and replacements_map != %{}) or is_binary(base) do
      input
      |> as_html_tree()
      |> LazyHTML.Tree.postwalk(fn
        {"a", attrs, children} = node ->
          case List.keyfind(attrs, "href", 0) do
            {"href", href} ->
              href = resolve_relative_link(href, base) || href
              # the same normalisation callers use for the map's keys
              normalised = URIs.normalise_for_comparison(href)

              new_href =
                case is_map(replacements_map) &&
                       (Map.get(replacements_map, normalised) ||
                          (is_function(fallback_match_fn) &&
                             fallback_match_fn.(replacements_map, normalised))) do
                  nil -> href
                  false -> href
                  new_href -> new_href
                end

              {"a",
               maybe_add_nofollow(List.keyreplace(attrs, "href", 0, {"href", new_href}), href),
               children}

            nil ->
              node
          end

        node ->
          node
      end)
    else
      input
    end
  end

  @doc """
  Prepares links in HTML content for local (browser) rendering: makes local links use
  LiveView navigation and adds `rel="nofollow noopener"` to external links that don't
  already carry a `rel` attribute.

  ## Examples

      > prepare_links_for_local_render("<a href=\"/path\">Link</a>")
      "<a href=\"/path\" data-phx-link=\"redirect\" data-phx-link-state=\"push\">Link</a>"
  """
  def prepare_links_for_local_render(content)
      when is_binary(content) and byte_size(content) > 20 do
    base = URIs.base_url()

    # most post bodies contain no links at all, so skip the regex engine unless there's an anchor to rewrite
    maybe_replace(content, "<a ", fn content ->
      Regex.replace(~r/<a ([^>]*?)href="([^"]*)"([^>]*)>/, content, fn _, pre, href, post ->
        link_tag(href, pre, post, base)
      end)
    end)
  end

  def prepare_links_for_local_render(content), do: content

  # keep old name as alias for call sites in pinned deps
  def make_local_links_live(content), do: prepare_links_for_local_render(content)

  defp link_tag("/" <> _ = href, pre, post, _base),
    do: ~s(<a #{pre}href="#{href}"#{post} data-phx-link="redirect" data-phx-link-state="push">)

  defp link_tag("http" <> _ = href, pre, post, base) do
    if String.starts_with?(href, base) do
      # absolute local URL — strip origin and recurse as relative path
      link_tag(String.replace_leading(href, base, ""), pre, post, base)
    else
      other_attrs = pre <> post

      if String.contains?(other_attrs, "nofollow"),
        do: ~s(<a #{other_attrs}href="#{href}">),
        else: ~s(<a rel="nofollow noopener" #{other_attrs}href="#{href}">)
    end
  end

  defp link_tag(href, pre, post, _base),
    do: ~s(<a #{pre}href="#{href}"#{post}>)

  def prepare_links_for_remote_render(content, format, base_url \\ nil, opts \\ [])

  def prepare_links_for_remote_render(content, :markdown, base_url, opts)
      when is_binary(content) and byte_size(content) > 10 do
    base_url = base_url || URIs.base_url()

    # `hashtag_html: false` keeps hashtag links markdown, for where the result must stay pure markdown (eg. an AP object's `source`)
    hashtag_html? = Keyword.get(opts, :hashtag_html, true)

    # every branch below needs a markdown link, so `](` is a sound pre-check
    maybe_replace(content, "](", fn content ->
      # Single pass: handles images, hashtag links (emitting HTML with class/rel for GH #1754), and regular links. `rest` keeps an optional link title.
      Regex.replace(~r/(!?)\[([^\]]*)\]\(([^)\s]+)((?:\s[^)]*)?)\)/, content, fn
        full, bang, text, target, rest ->
          case resolve_relative_link(target, base_url) do
            nil ->
              full

            # only a root-relative `/hashtag/` link is one of our hashtags
            url when bang == "" and hashtag_html? ->
              case {text, target} do
                {"#" <> _, "/hashtag/" <> _} ->
                  ~s(<a class="hashtag" rel="tag ugc" href="#{url}">#{text}</a>)

                _ ->
                  "[#{text}](#{url}#{rest})"
              end

            url ->
              "#{bang}[#{text}](#{url}#{rest})"
          end
      end)
    end)
  end

  def prepare_links_for_remote_render(content, :html, base_url, _opts)
      when is_binary(content) and byte_size(content) > 10 do
    base_url = base_url || URIs.base_url()

    maybe_replace(content, ~s(href="), fn content ->
      Regex.replace(~r/href="([^"]*)"/, content, fn full, href ->
        case resolve_relative_link(href, base_url) do
          nil -> full
          url -> ~s(href="#{url}")
        end
      end)
    end)
  end

  def prepare_links_for_remote_render(content, _, _, _), do: content

  # Resolves a link without a scheme (`x`, `/x`, `//host/x`) against `base` (RFC 3986), so it points to the same place wherever it is shown. Returns nil for links to leave as they are: absolute (incl. `mailto:`), in-page `#anchors`, and empty. Common absolute links match a clause head, so only the rest are parsed.
  defp resolve_relative_link(_href, nil), do: nil
  defp resolve_relative_link("https://" <> _, _base), do: nil
  defp resolve_relative_link("http://" <> _, _base), do: nil
  defp resolve_relative_link("#" <> _, _base), do: nil
  defp resolve_relative_link("", _base), do: nil

  defp resolve_relative_link(href, base) do
    case URI.parse(href) do
      %URI{scheme: nil} = uri -> base |> URI.merge(uri) |> URI.to_string()
      _ -> nil
    end
  end

  # keep old name as alias for call sites in pinned deps
  def make_links_absolute(content, format, base_url \\ nil),
    do: prepare_links_for_remote_render(content, format, base_url)

  @doc """
  Extracts URLs from HTML content using LazyHTML.

  Accepts string, LazyHTML struct, or tree as input.
  Returns {:ok, %{html: LazyHTML struct, urls: [url, ...]}} or nil for blank input.

  Filters out mention and hashtag anchors, so their URLs aren't unfurled as link previews: skips any anchor whose `class` includes `mention`, `hashtag`, `u-url` or `h-card`, or whose `rel` includes `tag`. 
  `u-url`/`h-card` are microformats2 and `rel="tag"` is a standard rel; this is a heuristic net, the authoritative exclusion is the AP `tag` array handled upstream. 
  Pass `include_mentions: true` to keep them.

  ## Examples

      iex> {:ok, %{html: %LazyHTML{resource: _}, urls: ["http://foo.com"]}} = Bonfire.Common.Text.extract_urls_from_html("<a href='http://foo.com'>foo</a>")

      iex> {:ok, %{html: %LazyHTML{resource: _}, urls: []}} = Bonfire.Common.Text.extract_urls_from_html("<div>no valid links</div><a href='/'>test</a><a href='mailto:test@example.com'>test</a>")
      
      iex> {:ok, %{html: %LazyHTML{resource: _}, urls: ["/"]}} = Bonfire.Common.Text.extract_urls_from_html("<div>including relative links</div><a href='/'>test</a>", allow_relative: true)

      iex> {:ok, %{html: %LazyHTML{resource: _}, urls: ["mailto:test@example.com"]}} = Bonfire.Common.Text.extract_urls_from_html("<div>no non-HTTP links</div><a href='/'>test</a><a href='mailto:test@example.com'>test</a>", allow_non_http: true)

      iex> {:ok, %{html: %LazyHTML{resource: _}, urls: ["ftp://test@example.com"]}} = Bonfire.Common.Text.extract_urls_from_html("<div>no non-HTTP links</div><a href='/'>test</a><a href='ftp://test@example.com'>test</a>", allow_non_http: true)

      iex> {:ok, %{urls: []}} = Bonfire.Common.Text.extract_urls_from_html(~s(<a href="https://mastodon.social/@bob" class="u-url mention">@bob</a>))

      iex> {:ok, %{urls: []}} = Bonfire.Common.Text.extract_urls_from_html(~s(<a href="https://mastodon.social/tags/x" class="mention hashtag" rel="tag">#x</a>))

      iex> {:ok, %{urls: ["https://mastodon.social/@bob"]}} = Bonfire.Common.Text.extract_urls_from_html(~s(<a href="https://mastodon.social/@bob" class="u-url mention">@bob</a>), include_mentions: true)

      iex> Bonfire.Common.Text.extract_urls_from_html(nil)
      nil

      iex> Bonfire.Common.Text.extract_urls_from_html("")
      nil
  """
  def extract_urls_from_html(html_content, opts \\ [])
  def extract_urls_from_html(nil, _opts), do: nil
  def extract_urls_from_html("", _opts), do: nil

  def extract_urls_from_html(input, opts) do
    html =
      input
      |> as_lazy_html()

    # 2.2 markup net (see @doc): drop mention/hashtag anchors so they aren't unfurled, unless the caller opts to keep them
    selector =
      if opts[:include_mentions] do
        "a[href]"
      else
        "a[href]:not(.mention):not(.hashtag):not(.u-url):not(.h-card):not([rel~=\"tag\"])"
      end

    urls =
      html
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("href")
      |> Enum.filter(fn url ->
        String.starts_with?(url, ["http://", "https://"]) or
          (opts[:allow_non_http] == true and
             (String.starts_with?(url, "mailto:") or String.contains?(url, "://"))) or
          (opts[:allow_relative] == true and String.starts_with?(url, "/"))
      end)

    {:ok,
     %{
       html: html,
       urls: urls
     }}
  end

  @doc """
  Converts markdown checkboxes to HTML checkboxes.

  ## Examples

      > markdown_checkboxes("* [ ] task\n* [x] done")
      "<ul><li><input type='checkbox'> task</li><li><input type='checkbox' checked='checked'> done</li></ul>"
  """
  def markdown_checkboxes(text) when is_binary(text) do
    text
    |> replace_checked_boxes()
    |> replace_unchecked_boxes()
  end

  defp replace_checked_boxes(text) do
    if String.match?(text, checkbox_regex_checked()) do
      String.replace(text, checkbox_regex_checked(), @checked_box)
    else
      text
    end
  end

  defp replace_unchecked_boxes(text) do
    if String.match?(text, checkbox_regex_unchecked()) do
      String.replace(text, checkbox_regex_unchecked(), @unchecked_box)
    else
      text
    end
  end

  @doc """
  Lists checked boxes from the text.

  ## Examples

      > list_checked_boxes("* [x] done")
      [["done"]]
  """
  def list_checked_boxes(text) do
    regex_list(checkbox_regex_checked_line(), text)
  end

  @doc """
  Lists unchecked boxes from the text.

  ## Examples

      > list_unchecked_boxes("* [ ] task")
      [["task"]]
  """
  def list_unchecked_boxes(text) do
    regex_list(checkbox_regex_unchecked_line(), text)
  end

  @doc """
  Lists all checkboxes from the text.

  ## Examples

      > list_checkboxes("* [ ] task\n* [x] done")
      [[" ", "task"], [" ", "done"]]
  """
  def list_checkboxes(text) do
    regex_list(checkbox_regex_checkbox_line(), text)
  end

  def regex_list(regex, text) when is_binary(text) and text != "" do
    Regex.scan(regex, text)
  end

  def regex_list(_text, _regex), do: nil

  @doc """
  Converts the first character of a binary to uppercase.

  ## Examples

      iex> upcase_first("hello")
      "Hello"
  """
  def upcase_first(<<first::utf8, rest::binary>>),
    do: String.upcase(<<first::utf8>>) <> rest

  def upcase_first(_), do: nil

  @doc """
  Converts a string to CamelCase.

  ## Examples

      iex> camelise("hello world")
      "HelloWorld"
  """
  def camelise(str) do
    words = ~w(#{str})

    Enum.into(words, [], fn word -> upcase_first(word) end)
    |> to_string()
  end

  @doc """
  Renders templated content if the `Solid` library is enabled.

  ## Examples

      > maybe_render_templated("Hello {{name}}", %{name: "World"})
      "Hello World"
  """
  defp template_quote_regex, do: ~r/&quot;/

  def maybe_render_templated(templated_content, data)
      when is_binary(templated_content) and is_map(data) do
    if Extend.module_enabled?(Solid) and String.contains?(templated_content, "{{") do
      templated_content = templated_content |> String.replace(template_quote_regex(), "\"")

      with {:ok, template} <- Solid.parse(templated_content),
           {:ok, rendered, errors} <- Solid.render(template, data) do
        # eg. an undefined filter, which renders as empty
        if errors != [], do: warn(errors, "Errors while rendering the template")

        rendered
        |> to_string()
      else
        {:error, errors, _partial} ->
          error(errors, templated_content)
          templated_content

        {:error, error} ->
          error(error, templated_content)
          templated_content
      end
    else
      debug("Solid not used in block or not enabled - skipping parse/render template")
      templated_content
    end
  end

  def maybe_render_templated(content, data) do
    if Keyword.keyword?(data) do
      maybe_render_templated(content, Map.new(data))
    else
      warn(data, "Did not get a data as a Keyword or Map, so can't parse/render template")
      content
    end
  end

  @doc """
  Converts an English conjugated verb to its infinitive form using the `Verbs` library. Currently only supports irregular verbs.

  ## Examples

      > verb_infinitive("running")
      "run"
  """
  def verb_infinitive(verb_conjugated) do
    with true <- Extend.module_enabled?(Irregulars),
         [{infinitive, _}] <-
           Enum.filter(Irregulars.verb_forms(), fn {_infinitive, conjugations} ->
             verb_conjugated in conjugations
           end) do
      infinitive
    else
      _ ->
        nil
    end
  end

  @doc """
  Converts input to a LazyHTML struct.

  Accepts string, tree, or LazyHTML struct.

  ## Examples

      iex> %LazyHTML{resource: _} = as_lazy_html("<b>hi</b>")
      
      iex> %LazyHTML{resource: _} = as_lazy_html([{"b", [], ["hi"]}])
      
      iex> %LazyHTML{resource: _} = as_lazy_html(%LazyHTML{resource: nil}) 
  """
  def as_lazy_html(nil), do: nil
  def as_lazy_html(%LazyHTML{} = html), do: html
  def as_lazy_html(text) when is_binary(text), do: LazyHTML.from_fragment(text)
  def as_lazy_html(tree) when is_list(tree), do: LazyHTML.from_tree(tree)

  @doc """
  Converts input to a LazyHTML tree.

  Accepts string, LazyHTML struct, or tree.

  ## Examples

      iex> as_html_tree("<b>hi</b>")
      [{"b", [], ["hi"]}]

      iex> as_html_tree([{"b", [], ["hi"]}])
      [{"b", [], ["hi"]}]

      iex> as_html_tree(LazyHTML.from_fragment("<b>hi</b>"))
      [{"b", [], ["hi"]}]

  Accepts string, LazyHTML struct, or tree.

  ## Examples

      iex> as_html_tree("<b>hi</b>")
      [{"b", [], ["hi"]}]

      iex> as_html_tree([{"b", [], ["hi"]}])
      [{"b", [], ["hi"]}]

      iex> as_html_tree(LazyHTML.from_fragment("<b>hi</b>"))
      [{"b", [], ["hi"]}]
  """
  @doc """
  Strips the last element matching `tag` from an HTML tree if all its non-whitespace
  children satisfy `match_fn`.

  Operates on a LazyHTML tree (list of tuples) to avoid extra string/tree conversions.
  Returns the tree unchanged if the last element doesn't match.

  ## Examples

      iex> match_fn = fn {"a", [{"href", "/hashtag/" <> _}], _} -> true; _ -> false end
      iex> strip_trailing_element([{"p", [], ["Hello"]}, {"p", [], [{"a", [{"href", "/hashtag/ABC"}], ["#test"]}]}], "p", match_fn)
      [{"p", [], ["Hello"]}]

      iex> match_fn = fn {"a", [{"href", "/hashtag/" <> _}], _} -> true; _ -> false end
      iex> strip_trailing_element([{"p", [], ["Hello"]}, {"p", [], ["not a hashtag"]}], "p", match_fn)
      [{"p", [], ["Hello"]}, {"p", [], ["not a hashtag"]}]
  """
  def strip_trailing_element(tree, tag, match_fn)
      when is_list(tree) and is_binary(tag) and is_function(match_fn, 1) do
    case List.last(tree) do
      {^tag, _attrs, children} when is_list(children) ->
        non_whitespace =
          Enum.reject(children, fn
            text when is_binary(text) -> String.trim(text) == ""
            _ -> false
          end)

        if non_whitespace != [] and Enum.all?(non_whitespace, match_fn) do
          List.delete_at(tree, -1)
        else
          tree
        end

      _ ->
        tree
    end
  end

  def strip_trailing_element(other, _tag, _match_fn), do: other

  @doc """
  Adds `class` to the last element matching `tag` in an HTML tree if all its
  non-whitespace children satisfy `match_fn`.

  Operates on a LazyHTML tree (list of tuples) to avoid extra string/tree conversions.
  Returns the tree unchanged if the last element doesn't match.

  ## Examples

      iex> match_fn = fn {"a", [{"href", "/hashtag/" <> _}], _} -> true; _ -> false end
      iex> mark_trailing_element([{"p", [], ["Hello"]}, {"p", [], [{"a", [{"href", "/hashtag/ABC"}], ["#test"]}]}], "p", "invisible", match_fn)
      [{"p", [], ["Hello"]}, {"p", [{"class", "invisible"}], [{"a", [{"href", "/hashtag/ABC"}], ["#test"]}]}]

      iex> match_fn = fn {"a", [{"href", "/hashtag/" <> _}], _} -> true; _ -> false end
      iex> mark_trailing_element([{"p", [], ["Hello"]}, {"p", [], ["not a hashtag"]}], "p", "invisible", match_fn)
      [{"p", [], ["Hello"]}, {"p", [], ["not a hashtag"]}]
  """
  def mark_trailing_element(tree, tag, class, match_fn)
      when is_list(tree) and is_binary(tag) and is_function(match_fn, 1) do
    case List.last(tree) do
      {^tag, attrs, children} when is_list(children) ->
        non_whitespace =
          Enum.reject(children, fn
            text when is_binary(text) -> String.trim(text) == ""
            _ -> false
          end)

        if non_whitespace != [] and Enum.all?(non_whitespace, match_fn) do
          marked = {tag, [{"class", class} | attrs], children}
          List.replace_at(tree, -1, marked)
        else
          tree
        end

      _ ->
        tree
    end
  end

  def mark_trailing_element(other, _tag, _class, _match_fn), do: other

  @doc """
  Marks the last paragraph of an HTML body `invisible` when it holds only links to hashtags on this instance (relative `/hashtag/…` or absolute under `base_url`), as Mastodon hides a trailing line of hashtags: the post stays tagged, but the line isn't shown under its text.

  Takes and returns an HTML string, or an HTML tree for callers already working on one. A body with nothing to mark is returned as it came, not re-serialised.

  ## Examples

      iex> mark_trailing_hashtags(~s(<p>Hello</p>\\n<p><a href="/hashtag/test">#test</a></p>\\n))
      ~s(<p>Hello</p>\\n<p class="invisible"><a href="/hashtag/test">#test</a></p>)

      iex> mark_trailing_hashtags(~s(<p>Hello <a href="/hashtag/test">#test</a></p>))
      ~s(<p>Hello <a href="/hashtag/test">#test</a></p>)
  """
  def mark_trailing_hashtags(html, base_url \\ nil)

  def mark_trailing_hashtags(html, base_url) when is_binary(html) do
    # most bodies have no hashtag at all, so skip parsing unless there's one to look at
    if String.contains?(html, "/hashtag/") do
      tree = as_html_tree(String.trim(html))
      marked = mark_trailing_hashtags(tree, base_url)

      if marked == tree, do: html, else: LazyHTML.Tree.to_html(marked)
    else
      html
    end
  end

  def mark_trailing_hashtags(tree, base_url) when is_list(tree) do
    local_hashtag_prefix = (base_url || URIs.base_url()) <> "/hashtag/"

    mark_trailing_element(tree, "p", "invisible", fn
      {"a", attrs, _} ->
        case List.keyfind(attrs, "href", 0) do
          {"href", "/hashtag/" <> _} -> true
          {"href", href} -> String.starts_with?(href, local_hashtag_prefix)
          _ -> false
        end

      _ ->
        false
    end)
  end

  def mark_trailing_hashtags(other, _base_url), do: other

  def as_html_tree(nil), do: nil
  def as_html_tree(tree) when is_list(tree), do: tree
  def as_html_tree(input), do: as_lazy_html(input) |> LazyHTML.to_tree()

  @doc """
  Normalizes HTML content and returns a string.
  Accepts string, LazyHTML struct, or HTML syntax tree as input.

  Trims all leading and trailing `<p><br/></p>`, `<br/>`, and empty `<p></p>` tags.

  ## Examples

      iex> as_html("<p>Test</p>")
      "<p>Test</p>"

      iex> as_html("<p><br/></p><p></p><br/>")
      ""

      iex> as_html("<p><br/></p><p></p><p><br/></p><br/>")
      ""

      iex> as_html("<p><br/></p><br/>")
      ""

      iex> as_html("<p></p>")
      ""

      iex> as_html("<br/>")
      ""

      iex> as_html("<p><br/></p>Hello<br/>")
      "Hello"

      iex> as_html("<p><br/></p><p>Test</p><br/>")
      "<p>Test</p>"

      iex> as_html("<p><br/></p><p>Test</p><p></p><br/>")
      "<p>Test</p>"

      iex> as_html("<p><br/></p><p>Test</p><p>More</p><br/>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p><br/></p><p>Test</p><p>More</p><p></p><br/>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p><br/></p><p></p><p>Test</p><p>More</p><p></p><br/>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p><br/></p><p>Test</p><p>More</p><p>Even</p><br/>")
      "<p>Test</p><p>More</p><p>Even</p>"

      iex> as_html("<p><br/></p><p>Test</p><p>More</p><p>Even</p><p></p><br/>")
      "<p>Test</p><p>More</p><p>Even</p>"

      iex> as_html("<p><br/></p><p>Test</p><p>More</p><p>Even</p><p><br/></p><br/>")
      "<p>Test</p><p>More</p><p>Even</p>"

      iex> as_html("<p>Test</p><p>More</p>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p>Test</p><p></p>")
      "<p>Test</p>"

      iex> as_html("Test<br/>")
      "Test"

      iex> as_html("<p>Test</p>More<br/>")
      "<p>Test</p>More"

      iex> as_html("<p>Test</p><p>More</p><p></p>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p>Test</p><p>More</p><p><br/></p>")
      "<p>Test</p><p>More</p>"

      iex> as_html("<p>Test</p><p>More</p><p>Even</p>")
      "<p>Test</p><p>More</p><p>Even</p>"

      iex> as_html("<p>Test</p><p>More</p><p>Even</p><p></p>")
      "<p>Test</p><p>More</p><p>Even</p>"

      iex> as_html("Test<p>More</p><p>Even</p><p><br/></p>")
      "Test<p>More</p><p>Even</p>"

      iex> as_html("")
      ""
  """
  def as_html(nil), do: nil

  def as_html(input) do
    # Helper to detect empty paragraph node
    br_or_empty_paragraph? = fn
      {"br", _, _} -> true
      {"p", _, [{"br", _, _}]} -> true
      {"p", _, []} -> true
      {"p", _, [""]} -> true
      _ -> false
    end

    # Trim all leading/trailing <p><br/></p>, <br/>, and empty <p></p> nodes
    as_html_tree(input)
    |> Enum.drop_while(fn node -> br_or_empty_paragraph?.(node) end)
    |> Enum.reverse()
    |> Enum.drop_while(fn node -> br_or_empty_paragraph?.(node) end)
    |> Enum.reverse()
    |> LazyHTML.Tree.to_html()
  end

  defp maybe_add_nofollow(attrs, href) do
    if String.starts_with?(href, ["http://", "https://"]) and
         !List.keymember?(attrs, "rel", 0),
       do: [{"rel", "nofollow noopener"} | attrs],
       else: attrs
  end
end
