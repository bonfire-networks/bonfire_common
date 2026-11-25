if Code.ensure_loaded?(HtmlSanitizeEx) do
  defmodule Bonfire.Common.Text.SanitizeImportedHTML do
    @moduledoc """
    Sanitises the HTML of an article imported from another site (eg. Ghost, WordPress), keeping more of its structure than `Bonfire.Common.Text.SanitizeHTML`: figures and their captions, sections, galleries, `picture`, `details`, audio and video players, superscripts and subscripts, a text's writing direction (`dir`), a link's `rel` tokens, and the source's own card and block classes (`kg-*`, `wp-block-*`, alignment, image size, `language-*`). Everything `SanitizeHTML` allows is allowed too. Anything that could run is removed with its content: scripts, styles, forms and their controls, SVG, iframes, objects and embeds; as are event, `style` and `data-*` attributes, and URLs that aren't web addresses.

    The allow-lists are the module attributes below: add a tag, an attribute or a class pattern there.
    """
    use HtmlSanitizeEx, extend: Bonfire.Common.Text.SanitizeHTML

    alias Bonfire.Common.Text.SanitizeHTML

    # removed along with their content, which is code or controls rather than text to read
    @dropped_tags ~w(script style noscript template svg math iframe object embed form button input select textarea option)

    # structure kept (besides what `SanitizeHTML` keeps), with their `class` filtered as below
    @structure_tags ~w(figure figcaption section aside cite caption tfoot picture details summary div span p a img code pre blockquote ul ol li table thead tbody tr th td h1 h2 h3 h4 h5 h6 sup sub)

    # the text containers whose writing direction is kept, and its values
    @dir_tags ~w(p div span h1 h2 h3 h4 h5 h6 li blockquote figcaption section aside)
    @dir_values ~w(ltr rtl auto)

    # a link's `rel` keeps these tokens, each on its own
    @rel_tokens ~w(noopener noreferrer nofollow ugc sponsored)

    # players: kept with `controls` added, since the source's own player needed its scripts
    @media_tags ~w(audio video)

    # the attributes kept per tag, as they are
    @tag_attributes %{
      "img" => ~w(width height alt title sizes),
      "source" => ~w(type sizes),
      "audio" => ~w(preload loop muted controls),
      "video" => ~w(preload width height loop muted playsinline controls),
      "a" => ~w(title name)
    }

    # the attributes kept per tag when they're a web address (`mailto:` too for a link)
    @tag_uri_attributes %{
      "img" => ~w(src),
      "source" => ~w(src),
      "audio" => ~w(src),
      "video" => ~w(src poster),
      "a" => ~w(href)
    }

    # the attributes kept per tag only with one of these values
    @tag_attribute_values %{
      {"img", "loading"} => ~w(lazy eager),
      {"a", "target"} => ~w(_blank)
    }

    # the tags whose `srcset` is kept when every candidate in it is a web address
    @srcset_tags ~w(img source)

    # the source's own classes: Ghost's cards, WordPress' blocks, their alignment and the image size the author picked, and code languages
    @class_pattern ~r/\A(kg-[a-z0-9-]+|wp-(block|element)-[a-z0-9-]+|align(left|right|center|wide|full)|has-text-align-[a-z]+|size-(thumbnail|medium|medium_large|large|full)|language-[a-z0-9+#-]+)\z/

    @web_schemes ["http", "https"]

    def scrub({tag, _attributes, _children}) when tag in @dropped_tags, do: ""

    def scrub({tag, attributes, children}) when tag in @media_tags do
      attributes = scrub_attrs(tag, attributes)

      {tag,
       if(List.keymember?(attributes, "controls", 0),
         do: attributes,
         else: attributes ++ [{"controls", "controls"}]
       ), children}
    end

    def scrub({"source", attributes, children}),
      do: {"source", scrub_attrs("source", attributes), children}

    def scrub({tag, attributes, children}) when tag in @structure_tags,
      do: {tag, scrub_attrs(tag, attributes), children}

    # only the classes that are the source's own or ours are kept, token by token, so an imported class can't take over one of ours (eg. a utility class); the attribute goes when none is left
    def scrub_attribute(tag, {"class", value})
        when (tag in @structure_tags or tag in @media_tags) and is_binary(value) do
      case value
           |> :binary.split([" ", "\t", "\n", "\r", "\f"], [:global, :trim_all])
           |> Enum.filter(&(Regex.match?(@class_pattern, &1) or SanitizeHTML.allowed_class?(&1))) do
        [] -> nil
        tokens -> {"class", Enum.join(tokens, " ")}
      end
    end

    def scrub_attribute(tag, {"srcset", value}) when tag in @srcset_tags,
      do: if(web_srcset?(value), do: {"srcset", value})

    def scrub_attribute(tag, {"dir", value}) when tag in @dir_tags and value in @dir_values,
      do: {"dir", value}

    # kept token by token (eg. `noopener noreferrer`), and dropped when none is left
    def scrub_attribute("a", {"rel", value}) when is_binary(value) do
      case value
           |> :binary.split([" ", "\t", "\n", "\r", "\f"], [:global, :trim_all])
           |> Enum.filter(&(&1 in @rel_tokens)) do
        [] -> nil
        tokens -> {"rel", Enum.join(tokens, " ")}
      end
    end

    def scrub_attribute(tag, {attribute, value}) when is_map_key(@tag_attributes, tag) do
      cond do
        attribute in @tag_attributes[tag] ->
          {attribute, value}

        attribute in Map.get(@tag_uri_attributes, tag, []) ->
          schemes = if tag == "a", do: @web_schemes ++ ["mailto"], else: @web_schemes
          HtmlSanitizeEx.Scrubber.URI.scrub_attribute(tag, {attribute, value}, schemes)

        value in Map.get(@tag_attribute_values, {tag, attribute}, []) ->
          {attribute, value}

        true ->
          nil
      end
    end

    # every candidate of a `srcset` (`url width`, comma separated) has to be a web address, else the attribute goes
    defp web_srcset?(value) when is_binary(value) do
      value
      |> String.split(",", trim: true)
      |> Enum.all?(fn candidate ->
        case candidate |> String.trim() |> String.split(~r/\s+/, parts: 2) do
          [url | _] -> URI.parse(url).scheme in @web_schemes
          _ -> false
        end
      end)
    end

    defp web_srcset?(_), do: false

    defp scrub_attrs(tag, attributes) do
      attributes
      |> Enum.map(&scrub_attribute(tag, &1))
      |> Enum.reject(&is_nil/1)
    end
  end
end
