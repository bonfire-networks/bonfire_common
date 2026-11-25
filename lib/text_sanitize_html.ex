if Code.ensure_loaded?(HtmlSanitizeEx) do
  defmodule Bonfire.Common.Text.SanitizeHTML do
    use HtmlSanitizeEx, extend: :markdown_html

    allow_tag_with_this_attribute_values("a", "target", ["_blank"])
    allow_tag_with_this_attribute_values("a", "rel", ["noopener", "noreferrer", "nofollow"])

    # the classes remote posts use for mentions, hashtags, link text and the like (as Mastodon's own sanitiser keeps), kept token by token as a post has several per element (e.g. `u-url mention`)
    @allow_classes MapSet.new(["invisible", "mention", "hashtag", "h-card", "u-url", "ellipsis"])
    @class_tags ["a", "p", "span", "div"]

    @doc "Whether `class` is one of the classes kept on a remote post (see `Bonfire.Common.Text.SanitizeImportedHTML`, which keeps them too)."
    def allowed_class?(class), do: MapSet.member?(@allow_classes, class)

    # only the `class` value is split (on ASCII whitespace, with `:binary.split/3`, which is several times faster than `String.split/1` that handles all of Unicode's); the allowed tokens are looked up in a compile-time set, and the attribute is dropped when none is allowed
    def scrub_attribute(tag, {"class", value}) when tag in @class_tags and is_binary(value) do
      if MapSet.member?(@allow_classes, value) do
        # a single allowed class (the common case for p, span and div) needs no splitting
        {"class", value}
      else
        case value
             |> :binary.split([" ", "\t", "\n", "\r", "\f"], [:global, :trim_all])
             |> Enum.filter(&MapSet.member?(@allow_classes, &1)) do
          [] -> nil
          tokens -> {"class", Enum.join(tokens, " ")}
        end
      end
    end

    # a, p and span are already allowed by markdown_html, but its scrub/1 does not see the clause above, so they get a scrub/1 clause below that does; div is NOT in markdown_html's allowed tags at all

    # Workaround for allow_tag_with_this_attribute_values not hooking into scrub/1
    # for tags already registered by the base scrubber (span, p) or not registered at all (div).
    # See https://github.com/rrrene/html_sanitize_ex
    def scrub({"a", attributes, children}) do
      {"a", scrub_attrs("a", attributes), children}
    end

    def scrub({"span", attributes, children}) do
      {"span", scrub_attrs("span", attributes), children}
    end

    def scrub({"p", attributes, children}) do
      {"p", scrub_attrs("p", attributes), children}
    end

    def scrub({"div", attributes, children}) do
      case scrub_attrs("div", attributes) do
        [] -> children
        scrubbed -> {"div", scrubbed, children}
      end
    end

    defp scrub_attrs(tag, attributes) do
      attributes
      |> Enum.map(&scrub_attribute(tag, &1))
      |> Enum.reject(&is_nil/1)
    end
  end
end
