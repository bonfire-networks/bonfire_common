defmodule Bonfire.Common.Text do
  @moduledoc "Helpers for handling plain or rich text (markdown, HTML, etc)"

  use Untangle
  use Arrows
  use Bonfire.Common.E
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Config
  alias Bonfire.Common.Settings

  # @add_to_end "..."
  @sentence_seperator " "

  @checkbox_regex_unchecked ~r/\s\[\s\]/
  @checkbox_regex_unchecked_line ~r/\s\[\s\]\s(.*)$/mu
  @checkbox_regex_checked ~r/\s\[[X,x]\]/
  @checkbox_regex_checked_line ~r/\s\[[X,x]\]\s(.*)$/mu
  @checkbox_regex_checkbox_line ~r/^(\s*)[-|<li>]\s\[([ |X|x])\]\s(.*)$/mu
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
  Hashes the input using a specified algorithm.

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
  """
  def contains_html?(string), do: Regex.match?(~r/<\/?[a-z][\s\S]*>/i, string)

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
  Converts the input content from markdown to HTML if the markdown library is enabled.
  If the content starts with an HTML tag or if the markdown library is not enabled, it skips conversion.

      > Bonfire.Common.Text.maybe_markdown_to_html("*Hello World*", [])
      "<p><em>Hello World</em></p>"

      iex> Bonfire.Common.Text.maybe_markdown_to_html("<p>Hello</p>", [])
      "<p>Hello</p>"

      > Bonfire.Common.Text.maybe_markdown_to_html("Not markdown", [])
      "<p>Not markdown</p>"
  """
  def maybe_markdown_to_html(nothing, opts \\ [])

  def maybe_markdown_to_html(nothing, _opts)
      when not is_binary(nothing) or nothing == "" do
    nil
  end

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
  def maybe_markdown_to_html("<" <> _ = content, _opts) do
    warn("skipping processing of content that starts with an HTML tag")
    content
  end

  def maybe_markdown_to_html(content, opts) do
    # debug(content, "input")

    if markdown_library = choose_markdown_library(opts) do
      markdown_as_html(markdown_library, content, opts)
    else
      error("No markdown library seems to be enabled, skipping processing")
      content
    end
  end

  defp choose_markdown_library(opts) do
    default_library = MDEx
    initial_library = opts[:markdown_library] || Config.get(:markdown_library, default_library)

    cond do
      Extend.module_enabled?(initial_library, opts) ->
        initial_library

      initial_library == MDEx and Extend.module_enabled?(Earmark, opts) ->
        Earmark

      initial_library == Earmark and Extend.module_enabled?(MDEx, opts) ->
        MDEx

      true ->
        nil
    end
  end

  defp markdown_as_html(MDEx, content, opts) do
    with {:ok, html} <-
           [
             parse: [
               smart: false,
               relaxed_tasklist_matching: true,
               relaxed_autolinks: true
             ],
             render: [
               hardbreaks: true,
               # unsafe_: opts[:__unsafe__],
               # Allow rendering of raw HTML and potentially dangerous links
               _unsafe: opts[:__unsafe__] || opts[:sanitize] || false,
               # !opts[:sanitize] and !opts[:__unsafe__] # Escape raw HTML instead of clobbering it.
               escape: false
             ],
             extension: [
               strikethrough: true,
               tasklist: true,
               # can't use because things @ mentions are emails
               autolink: false,
               table: true,
               tagfilter: true,
               header_ids: ""
             ],
             features: [
               sanitize: opts[:sanitize] || false,
               # sanitize: opts[:__unsafe__], # sanitizes the HTML (but strips things like class and attributes)
               # TODO: auto-set appropriate theme based on user's daisy theme
               syntax_highlight_theme: "adwaita_dark"
             ]
           ]
           # |> Keyword.merge(opts)
           |> MDEx.to_html(content, ...) do
      html
    else
      e ->
        error(e)
        nil
    end
  end

  defp markdown_as_html_earmark(processor, content, opts) when processor in [Earmark, Makedown] do
    # NOTE: Makedown is a wrapper around Earmark and Makeup to support syntax highlighting of code blocks

    [
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
    |> Keyword.merge(opts)
    |> processor.as_html(content, ...)
    ~> markdown_checkboxes()
    |> debug("MD output for: #{content}")
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
      "hello-world!"

      iex> Bonfire.Common.Text.slug("Elixir Programming")
      "elixir-programming"

      iex> Bonfire.Common.Text.slug("Special & Characters")
      "special-&-characters"
  """
  def slug({_tag, _attrs, text, _extra}), do: slug(text)

  def slug(text) when is_list(text),
    do: text |> Enum.map(&md_tag_text/1) |> Enum.join("-") |> slug()

  def slug(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
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
  defp md_tag_text(text) when is_binary(text), do: text
  defp md_tag_text(_), do: ""

  @doc """
  Highlights code using Makeup or falls back to Phoenix.HTML if unsupported.

  ## Examples

      > code_syntax("defmodule Test {}", "test.ex")
      #=> "<pre><code class=\"highlight\">defmodule Test {}</code></pre>"
  """
  def code_syntax(text, filename) do
    if makeup_supported?(filename) do
      Makeup.highlight(text)
    else
      Phoenix.HTML.Tag.content_tag(:pre, Phoenix.HTML.Tag.content_tag(:code, text),
        class: "highlight"
      )
    end
  end

  defp makeup_supported?(filename) do
    (Extend.module_enabled?(Makeup) and
       Path.extname(filename) in [
         ".ex",
         ".exs",
         ".sface",
         ".heex",
         ".erl",
         ".hrl",
         ".escript",
         ".json",
         ".js",
         ".html",
         ".htm",
         ".diff",
         ".sql",
         ".gql",
         ".graphql"
       ]) ||
      filename in ["rebar.config", "rebar.config.script"] ||
      String.ends_with?(filename, ".app.src")
  end

  @doc """
  Sanitizes HTML content to ensure it is safe.

  It is recommended to call this before storing any that data is coming in from the user or from a remote instance

  ## Examples

      > maybe_sane_html("<script>alert('XSS')</script>")
      #=> "alert('XSS')" (if HtmlSanitizeEx is enabled)
  """
  def maybe_sane_html(content) do
    if Extend.module_enabled?(HtmlSanitizeEx) do
      HtmlSanitizeEx.markdown_html(content)
    else
      content
    end
  end

  @doc """
  Extracts plain text from HTML content.

  ## Examples

      iex> text_only("<div>Text</div>")
      "Text"

      iex> text_only({:safe, "<div>Safe Text</div>"})
      "Safe Text"
  """
  def text_only({:safe, content}), do: text_only(content)

  def text_only(content) when is_binary(content) do
    if Extend.module_enabled?(HtmlSanitizeEx) do
      HtmlSanitizeEx.strip_tags(content)
    else
      content
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
    end
  end

  def text_only(_content), do: nil

  @doc """
  Normalizes HTML content, handling various edge cases.

  ## Examples

      iex> maybe_normalize_html("<p>Test</p>")
      "Test"

      iex> maybe_normalize_html("<p><br/></p>")
      ""
  """
  def maybe_normalize_html("<p>" <> content) do
    # workaround for weirdness with Earmark's parsing of markdown within html
    maybe_normalize_html(content)
  end

  def maybe_normalize_html(html_string) when is_binary(html_string) do
    if Extend.module_enabled?(Floki) do
      with {:ok, fragment} <- Floki.parse_fragment(html_string) do
        Floki.raw_html(fragment)
      else
        e ->
          warn(e, "seems to be invalid HTML, converting to text-only instead")
          text_only(html_string)
      end
    else
      html_string
    end
    |> String.trim("<p><br/></p>")
    |> String.trim("<br/>")

    # |> debug(html_string)
  end

  @doc """
  Converts text to emotes if the Emote module is enabled.

  ## Examples

      iex> maybe_emote(":smile:", nil, [])
      "😄"
  """
  def maybe_emote(content, user \\ nil, custom_emoji \\ []) do
    if Extend.module_enabled?(Emote, user) do
      # debug(custom_emoji)

      Emote.convert_text(content,
        custom_fn: fn text -> maybe_other_custom_emoji(text, user) end,
        custom_emoji: custom_emoji
      )

      # |> debug()
    else
      content
    end
  end

  def maybe_other_custom_emoji(text, user) do
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

            " <img alt='#{label}' title='#{label}' class='emoji' data-emoji='#{text}' src='#{e(emoji, :url, nil) || emoji}' /> "
        end

      ["", family, icon, ""] ->
        " <img alt='#{text}' title='#{text}' class='emoji' src='https://api.iconify.design/#{family}/#{icon}.svg' /> "

      #     "<span iconify='#{family}:#{icon}' class='iconify' aria-hidden='true'>
      #   <img class='hidden' alt='#{text}' title='#{text}' src='https://api.iconify.design/#{family}/#{icon}.svg' onerror=\"this.src='https://api.iconify.design/ooui/article-not-found-ltr.svg'\" />
      # </span>"
      _ ->
        text
    end
  end

  @doc """
  Makes local links within content live.

  ## Examples

      > make_local_links_live("<a href=\"/path\">Link</a>")
      "<a href=\"/path\" data-phx-link=\"redirect\" data-phx-link-state=\"push\">Link</a>"
  """
  def make_local_links_live(content)
      when is_binary(content) and byte_size(content) > 20 do
    # local_instance = Bonfire.Common.URIs.base_url()

    content
    # handle internal links
    |> Regex.replace(
      ~r/(<a [^>]*href=\")\/(.+\")/U,
      ...,
      " \\1/\\2 data-phx-link=\"redirect\" data-phx-link-state=\"push\""
    )

    # |> debug(content)
  end

  def make_local_links_live(content), do: content

  @doc """
  Normalizes links in the content based on format.

  ## Examples

      > normalise_links("<a href=\"/pub/actors/foo\">Actor</a>", :markdown)
      "<a href=\"/character/foo\">Actor</a>"
  """
  def normalise_links(content, format \\ :markdown)

  def normalise_links(content, :markdown)
      when is_binary(content) and byte_size(content) > 20 do
    local_instance = Bonfire.Common.URIs.base_url()

    content
    # handle AP actors
    |> Regex.replace(
      ~r/(\()#{local_instance}\/pub\/actors\/(.+\))/U,
      ...,
      "\\1/character/\\2"
    )
    # handle AP objects
    |> Regex.replace(
      ~r/(\()#{local_instance}\/pub\/objects\/(.+\))/U,
      ...,
      "\\1/discussion/\\2"
    )
    # handle local links
    |> Regex.replace(
      ~r/(\]\()#{local_instance}(.+\))/U,
      ...,
      "\\1\\2"
    )

    # |> debug(content)
  end

  def normalise_links(content, _html)
      when is_binary(content) and byte_size(content) > 20 do
    local_instance = Bonfire.Common.URIs.base_url()

    content
    # special for MD links coming from milkdown
    # |> Regex.replace(~r/<(http.+)>/U, ..., " \\1 ")
    # handle AP actors
    |> Regex.replace(
      ~r/(<a [^>]*href=")#{local_instance}\/pub\/actors\/([^"]+)/U,
      ...,
      " \\1/character/\\2"
    )
    # handle AP objects
    |> Regex.replace(
      ~r/(<a [^>]*href=")#{local_instance}\/pub\/objects\/([^"]+)/U,
      ...,
      " \\1/discussion/\\2"
    )
    # handle local links
    |> Regex.replace(
      ~r/(<a [^>]*href=")#{local_instance}([^"]+)/U,
      ...,
      " \\1\\2"
    )
    # handle external links (in new tab)
    |> Regex.replace(~r/<a ([^>]*href="http[^"]+)/U, ..., " <a target=\"_blank\" \\1")

    # |> debug(content)
  end

  def normalise_links(content, _format), do: content

  @doc """
  Converts markdown checkboxes to HTML checkboxes.

  ## Examples

      > markdown_checkboxes("* [ ] task\n* [x] done")
      "<ul><li><input type='checkbox'> task</li><li><input type='checkbox' checked='checked'> done</li></ul>"
  """
  def markdown_checkboxes(text) do
    text
    |> replace_checked_boxes()
    |> replace_unchecked_boxes()
  end

  defp replace_checked_boxes(text) do
    if String.match?(text, @checkbox_regex_checked) do
      String.replace(text, @checkbox_regex_checked, @checked_box)
    else
      text
    end
  end

  defp replace_unchecked_boxes(text) do
    if String.match?(text, @checkbox_regex_unchecked) do
      String.replace(text, @checkbox_regex_unchecked, @unchecked_box)
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
    regex_list(@checkbox_regex_checked_line, text)
  end

  @doc """
  Lists unchecked boxes from the text.

  ## Examples

      > list_unchecked_boxes("* [ ] task")
      [["task"]]
  """
  def list_unchecked_boxes(text) do
    regex_list(@checkbox_regex_unchecked_line, text)
  end

  @doc """
  Lists all checkboxes from the text.

  ## Examples

      > list_checkboxes("* [ ] task\n* [x] done")
      [[" ", "task"], [" ", "done"]]
  """
  def list_checkboxes(text) do
    regex_list(@checkbox_regex_checkbox_line, text)
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
  def maybe_render_templated(templated_content, data)
      when is_binary(templated_content) and is_map(data) do
    if Extend.module_enabled?(Solid) and String.contains?(templated_content, "{{") do
      templated_content = templated_content |> String.replace("&quot;", "\"")

      with {:ok, template} <- Solid.parse(templated_content),
           {:ok, rendered} <- Solid.render(template, data) do
        rendered
        |> to_string()
      else
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
end
