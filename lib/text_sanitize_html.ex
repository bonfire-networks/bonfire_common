if Code.ensure_loaded?(HtmlSanitizeEx) do
  defmodule Bonfire.Common.Text.SanitizeHTML do
    use HtmlSanitizeEx, extend: :markdown_html

    allow_tag_with_this_attribute_values("a", "target", ["_blank"])
    allow_tag_with_this_attribute_values("a", "rel", ["noopener", "noreferrer", "nofollow"])

    @allow_classes ["invisible", "mention", "hashtag", "h-card"]

    # p and span are already allowed by markdown_html, so only need attribute values
    allow_tag_with_this_attribute_values("p", "class", @allow_classes)
    allow_tag_with_this_attribute_values("span", "class", @allow_classes)

    # div is NOT in markdown_html's allowed tags, so also needs a scrub/1 clause
    allow_tag_with_this_attribute_values("div", "class", @allow_classes)

    # Workaround for allow_tag_with_this_attribute_values not hooking into scrub/1
    # for tags already registered by the base scrubber (span, p) or not registered at all (div).
    # See https://github.com/rrrene/html_sanitize_ex
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
