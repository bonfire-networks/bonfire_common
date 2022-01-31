defmodule Bonfire.Common.Text do
  use Bonfire.Common.Utils
  require Logger

  @add_to_end "..."
  @sentence_seperator " "

  @checkbox_regex_unchecked ~r/\s\[\s\]/
  @checkbox_regex_unchecked_line ~r/\s\[\s\]\s(.*)$/mu
  @checkbox_regex_checked ~r/\s\[[X,x]\]/
  @checkbox_regex_checked_line ~r/\s\[[X,x]\]\s(.*)$/mu
  @checkbox_regex_checkbox_line ~r/^(\s*)[-|<li>]\s\[([ |X|x])\]\s(.*)$/mu
  @checked_box " <input type=\'checkbox\' checked=\'checked\'>"
  @unchecked_box " <input type=\'checkbox\'>"

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  def truncate(text, max_length \\ 250, add_to_end \\ nil)

  def truncate(text, max_length, add_to_end) do
    text = String.trim(text)

    if String.length(text) < max_length do
      text
    else
      if add_to_end do
        length_with_add_to_end = max_length - String.length(add_to_end)
        String.slice(text, 0, length_with_add_to_end) <> add_to_end
      else
        String.slice(text, 0, max_length)
      end
    end
  end

  def sentence_truncate(input, length \\ 250) do
    if(String.length(input)>length) do
      do_sentence_truncate(input, length)
    else
      input
    end
  end

  defp do_sentence_truncate(input, length \\ 250) do
    length_minus_1 = length - 1

    case input do
      <<result::binary-size(length_minus_1), @sentence_seperator, _::binary>> ->
        # Logger.info("the substring ends with seperator (eg. -)")
        # i. e. "abc-def-ghi", 8 or "abc-def-", 8 -> "abc-def"
        result

      <<result::binary-size(length), @sentence_seperator, _::binary>> ->
        #  Logger.info("the next char after the substring is seperator")
        # i. e. "abc-def-ghi", 7 or "abc-def-", 7 -> "abc-def"
        result

      <<_::binary-size(length)>> ->
        # Logger.info("it is the exact length string")
        # i. e. "abc-def", 7 -> "abc-def"
        input

      _ when length <= 1 ->
        # Logger.info("return an empty string if we reached the beginning of the string")
        ""

      _ ->
        # Logger.info("otherwise look into shorter substring")
        do_sentence_truncate(input, length_minus_1)
    end
  end

  def underscore_truncate(input, length \\ 250) do
    if(String.length(input)>length) do
      do_underscore_truncate(input, length)
    else
      input
    end
  end

  defp do_underscore_truncate(input, length \\ 250) do
    length_minus_1 = length - 1

    case input do
      <<result::binary-size(length_minus_1), "_", _::binary>> ->
        # Logger.info("the substring ends with seperator (eg. -)")
        # i. e. "abc-def-ghi", 8 or "abc-def-", 8 -> "abc-def"
        result

      <<result::binary-size(length), "_", _::binary>> ->
        #  Logger.info("the next char after the substring is seperator")
        # i. e. "abc-def-ghi", 7 or "abc-def-", 7 -> "abc-def"
        result

      <<_::binary-size(length)>> ->
        # Logger.info("it is the exact length string")
        # i. e. "abc-def", 7 -> "abc-def"
        input

      _ when length <= 1 ->
        # Logger.info("return an empty string if we reached the beginning of the string")
        ""

      _ ->
        # Logger.info("otherwise look into shorter substring")
        do_underscore_truncate(input, length_minus_1)
    end
  end

  def markdown_to_html(nothing) when not is_binary(nothing) or nothing=="" do
    nil
  end

  def markdown_to_html(content) do
    # IO.inspect(to_md: content)
    if module_enabled?(Earmark) do
      content
      |> Earmark.as_html!()
      |> markdown_checkboxes()
      |> external_links()
    else
      content
    end
  end

  def markdown_checkboxes(text) do
    text
    |> replace_checked_boxes
    |> replace_unchecked_boxes
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

  def list_checked_boxes(text) do
    regex_list(@checkbox_regex_checked_line, text)
  end

  def list_unchecked_boxes(text) do
    regex_list(@checkbox_regex_unchecked_line, text)
  end

  def list_checkboxes(text) do
    regex_list(@checkbox_regex_checkbox_line, text)
  end

  def regex_list(regex, text) when is_binary(text) and text !="" do
    Regex.scan(regex, text)
  end

  def regex_list(text, regex), do: nil

  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  def camelise(str) do
    words = ~w(#{str})

    Enum.into(words, [], fn word -> upcase_first(word) end)
    |> to_string
  end

end
