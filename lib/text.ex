defmodule Bonfire.Common.Text do
  import Bonfire.Common.Utils

  @regex_unchecked ~r/\s\[\s\]/
  @regex_unchecked_line ~r/\s\[\s\]\s(.*)$/mu
  @regex_checked ~r/\s\[[X,x]\]/
  @regex_checked_line ~r/\s\[[X,x]\]\s(.*)$/mu
  @regex_checkbox_line ~r/^(\s*)[-|<li>]\s\[([ |X|x])\]\s(.*)$/mu
  @checked_box " <input type=\'checkbox\' checked=\'checked\'>"
  @unchecked_box " <input type=\'checkbox\'>"

  def markdown_to_html(nothing) when not is_binary(nothing) or nothing=="" do
    nil
  end

  def markdown_to_html(content) do
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
    if String.match?(text, @regex_checked) do
      String.replace(text, @regex_checked, @checked_box)
    else
      text
    end
  end

  defp replace_unchecked_boxes(text) do
    if String.match?(text, @regex_unchecked) do
      String.replace(text, @regex_unchecked, @unchecked_box)
    else
      text
    end
  end

  def list_checked_boxes(text) do
    regex_list(@regex_checked_line, text)
  end

  def list_unchecked_boxes(text) do
    regex_list(@regex_unchecked_line, text)
  end

  def list_checkboxes(text) do
    regex_list(@regex_checkbox_line, text)
  end

  def regex_list(regex, text) when is_binary(text) and text !="" do
    Regex.scan(regex, text)
  end

  def regex_list(text, regex), do: nil

end
