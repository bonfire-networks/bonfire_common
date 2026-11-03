defmodule Bonfire.Common.Changelog.Formatter do
  @moduledoc """
  Keepachangelog formatter, `Versioce.Config.Changelog.formatter/0`, with extra sections for lines that no anchor matches.

  Versioce puts every unanchored line in one section. This splits them by their leading icon into the sections set in `config :versioce, :changelog, extra_sections: ["work in progress": ["🚧"], ...]`, listed first and in config order. Everything else, including lines that match no extra section, is left to `Versioce.Changelog.Formatter.Keepachangelog`.
  """
  @behaviour Versioce.Changelog.Formatter

  use Bonfire.Common.Config
  alias Versioce.Changelog.Formatter.Keepachangelog

  @impl Versioce.Changelog.Formatter
  def format(versions) do
    with {:ok, header} <- Keepachangelog.make_header(),
         {:ok, footer} <- Keepachangelog.make_footer(versions) do
      {:ok, Enum.join([header, Enum.map_join(versions, "\n", &version_to_str/1), footer], "\n")}
    end
  end

  @impl Versioce.Changelog.Formatter
  def version_to_str(%{sections: sections} = version) do
    {extra_sections, leftover} =
      Config.get([:changelog, :extra_sections], [], :versioce)
      |> Enum.map_reduce(sections.other, fn {name, icons}, lines ->
        {matched, rest} = Enum.split_with(lines, &String.starts_with?(&1, icons))
        {{name, matched}, rest}
      end)

    [version_heading, standard_sections] =
      %{version | sections: %{sections | other: leftover}}
      |> Keepachangelog.version_to_str()
      |> String.split("\n", parts: 2)

    extra_sections_str =
      for {name, [_ | _] = lines} <- extra_sections, into: "" do
        "### #{name |> to_string() |> String.capitalize()}\n" <>
          Enum.map_join(lines, "\n", &"- #{&1}") <> "\n\n"
      end

    version_heading <> "\n" <> extra_sections_str <> standard_sections
  end
end
