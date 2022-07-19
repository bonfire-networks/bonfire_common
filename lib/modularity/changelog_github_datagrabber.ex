if Bonfire.Common.Extend.module_enabled?(Versioce.Changelog.DataGrabber) do
defmodule Bonfire.Common.Changelog.Github.DataGrabber do
  @moduledoc """
  Datagrabber for changelog generation, `Versioce.Config.Changelog.datagrabber/0`

  Uses repository history to obtain and format data.
  """
  @behaviour Versioce.Changelog.DataGrabber

  import Where
  alias Bonfire.Common.Utils
  # alias Versioce.Changelog.Sections
  alias Versioce.Changelog.Anchors
  alias Versioce.Config

  @impl Versioce.Changelog.DataGrabber
  def get_data(new_version \\ "Unreleased") do
    {
      :ok,
      # new_version
      fetch_issues()
      |> prepare_data(new_version)
    }
  end

  def prepare_data(issues, new_version) do
    anchors = struct!(Anchors, Config.Changelog.anchors())
    issues
    |> prepare_sections(anchors, "#{new_version} (#{Date.utc_today})")
    |> List.wrap()
  end

  def fetch_issues(opts \\ []) do
    Application.ensure_all_started(:httpoison) # make HTTP client available in mix task

    org = Keyword.get(opts, :org, "bonfire-networks")

    closed_after = Keyword.get(opts, :closed_after) || Bonfire.Common.Config.get_ext(:versioce, [:changelog, :closed_after]) || Date.add(Date.utc_today, -Keyword.get(opts, :closed_in_last_days, 30))
    debug(closed_after, "Get issues closed after the ")

    token = Bonfire.Common.Config.get(:github_token) || System.get_env("GITHUB_TOKEN")
    # debug(token)

    with token when is_binary(token) and token !="" <- token,
    {:ok, %{body: body}} <- Neuron.query("""
    query {
      search(first: 100, type: ISSUE, query: "org:#{org} state:closed closed:>#{closed_after}") {
        issueCount
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          node {
            ... on Issue {
              number
              # createdAt
              # closedAt
              title
              url
              # bodyText
              # repository {
              #   name
              # }
              labels(first: 100) {
                edges {
                  node {
                    name
                    color
                  }
                }
              }
              assignees(first: 5) {
                edges {
                  node {
                    login
                  }
                }
              }
            }
          }
        }
      }
    }
    """,
    nil,
    url: "https://api.github.com/graphql",
    headers: [authorization: "Bearer #{token}"]) do
      body["data"]["search"]["edges"]
      |> Enum.map(&Utils.e(&1, "node", &1))
      # |> IO.inspect
    else e ->
      debug(e)
      []
    end
  end

  defp prepare_sections(groups, anchors, new_version) do

    %{
      version: new_version,
      sections: do_prepare_sections(groups, anchors, %Versioce.Changelog.Sections{})
    }
  end

  defp do_prepare_sections([], _anchors, acc), do: acc

  defp do_prepare_sections([issue | tail], anchors, acc) do

    labels = Utils.e(issue, "labels", "edges", [])
    |> Enum.map(&Utils.e(&1, "node", "name", nil))
    |> Utils.filter_empty(nil)

    grouping_texts = labels || [Utils.e(issue, "title", "")]

    do_prepare_sections(
      tail,
      anchors,
      add_to_section(issue, grouping_texts, anchors, acc)
    )
  end

  defp add_to_section(issue, grouping_texts, anchors, acc) do
    text = format_issue(issue)
    if text do
      anchors
      |> Map.from_struct()
      |> Enum.reduce_while(acc, fn {section, anchor_strings}, _ ->
        Enum.reduce_while(anchor_strings, false, fn anchor, _ ->
          cond do
            anchor in grouping_texts or Regex.match?(~r/^#{Regex.escape(anchor)}/, List.first(grouping_texts)) -> {:halt, section}
            true -> {:cont, false}
          end
        end)
        |> case do
          false -> {:cont, false}
          section -> {:halt, Map.update(acc, section, [text], &(&1 ++ [text]))}
        end
      end)
      |> case do
        false -> Map.update(acc, :other, [text], &([text] ++ &1))
        other -> other
      end
    else
      acc
    end
  end

  def format_issue(issue) do
    case Utils.e(issue, "title", nil) do
      title when is_binary(title) ->
        title = String.trim(title)
        number = Utils.e(issue, "number", nil)
        url = Utils.e(issue, "url", nil)
        assignees = Utils.e(issue, "assignees", "edges", [])
          |> Enum.map(&Utils.e(&1, "node", "login", nil))
          |> Enum.join(" & ")
        maybe_by = if assignees !="", do: "by #{assignees}"

        "#{title} [##{number}](#{url}) #{maybe_by}"
      _ -> nil
    end
  end

end
end
