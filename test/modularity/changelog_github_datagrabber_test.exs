defmodule Bonfire.Common.Changelog.Github.DataGrabberTest do
  @moduledoc """
  The changelog lists issues closed in a date window, so an issue that was closed without being fixed must not appear in it. GitHub records that in the close reason (`NOT_PLANNED` or `DUPLICATE`), and maintainers can also mark it with a `wontfix` or `duplicate` label. Both are checked here.

  Open issues are listed apart from the rest, so they can be checked before they go in a release changelog: a commit in the window that references an open issue goes under "Work in progress", and an open issue that no commit references goes under "New issues".

  The GitHub GraphQL API is mocked: the closed-issue search returns fixed issues, the open-issue search returns #10 and #20, the commit histories of `bonfire-app` and `bonfire_common` each return one commit that references #10, and every other query returns an empty result.
  """
  # not async: sets OS environment variables and application config
  use ExUnit.Case, async: false
  @moduletag :backend

  alias Bonfire.Common.Changelog.Github.DataGrabber
  alias Bonfire.Common.Changelog.Formatter

  @empty_search %{
    "data" => %{
      "search" => %{
        "issueCount" => 0,
        "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
        "edges" => []
      }
    }
  }

  @anchors %{
    added: ["✨"],
    changed: ["🚀"],
    deprecated: ["♻️"],
    removed: ["⚰️"],
    fixed: ["🐛"],
    security: ["🚨"]
  }

  setup do
    restore_env("GITHUB_TOKEN", "test-token")
    restore_env("CHANGES_CLOSED_AFTER", "2026-10-01")
    restore_env("CHANGES_CLOSED_BEFORE", nil)

    original_changelog_config = Application.get_env(:versioce, :changelog)

    Application.put_env(:versioce, :changelog,
      anchors: @anchors,
      extra_sections: ["work in progress": ["🚧"], "new issues": ["🆕"]],
      git_origin: nil
    )

    on_exit(fn ->
      if original_changelog_config,
        do: Application.put_env(:versioce, :changelog, original_changelog_config),
        else: Application.delete_env(:versioce, :changelog)
    end)

    mock_github(& &1)

    :ok
  end

  # `order` is applied to every list GitHub returns, to serve the same data in another order
  defp mock_github(order) do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.github.com/graphql", body: body} ->
        body = to_string(body)

        cond do
          String.contains?(body, "is:issue state:closed") -> json(issue_search_page(order))
          String.contains?(body, "is:issue state:open") -> json(open_issue_search_page(order))
          String.contains?(body, "defaultBranchRef") -> json(commit_history(body, order))
          String.contains?(body, "issue0: repository") -> json(open_issue_batch())
          true -> json(@empty_search)
        end

      %{method: :get} ->
        json([])
    end)
  end

  test "an issue closed without a commit is listed, unless closed as not planned or duplicate" do
    numbers =
      DataGrabber.fetch_issues(closed_after: ~D[2026-10-01])
      |> Enum.filter(&(&1["type"] == "issue"))
      |> Enum.map(& &1["number"])

    # positive control: an issue with no commit or PR still reaches the result
    assert 1 in numbers
    # existing label rule
    refute 4 in numbers
    refute 2 in numbers
    refute 3 in numbers
  end

  test "open issues are listed under Work in progress when a commit references them, and under New issues otherwise" do
    assert {:ok, [version]} = DataGrabber.get_versions()
    changelog = Formatter.version_to_str(version)

    work_in_progress = section(changelog, "Work in progress")
    assert work_in_progress =~ "- 🚧 Search filters [#10]"

    new_issues = section(changelog, "New issues")
    assert new_issues =~ "- 🆕 Issue 20 [#20]"
    refute new_issues =~ "#10"

    # positive control: the completed issue is listed, outside both sections
    assert changelog =~ "Issue 1 [#1]"
    refute work_in_progress <> new_issues =~ "#1]"
  end

  test "the changelog lists the oldest first, whatever order GitHub returns things in, so a new run only adds lines at the bottom" do
    assert {:ok, [version]} = DataGrabber.get_versions()
    changelog = Formatter.version_to_str(version)

    mock_github(&Enum.reverse/1)
    assert {:ok, [reversed_version]} = DataGrabber.get_versions()
    assert Formatter.version_to_str(reversed_version) == changelog

    # #5 was closed before #1
    assert position(changelog, "Issue 5 [#5]") < position(changelog, "Issue 1 [#1]")

    # the two "Add search filters #10" commits are one line, the older one first
    assert section(changelog, "Work in progress") =~ ~r/`bbbbbbb`.*`aaaaaaa`/
  end

  defp position(changelog, text) do
    case :binary.match(changelog, text) do
      {position, _} -> position
      :nomatch -> flunk("#{text} not in:\n#{changelog}")
    end
  end

  # the bullet lines under a `### heading`, up to the next heading
  defp section(changelog, heading) do
    case String.split(changelog, "### #{heading}\n", parts: 2) do
      [_, rest] -> rest |> String.split("\n#", parts: 2) |> List.first()
      _ -> flunk("no ### #{heading} section in:\n#{changelog}")
    end
  end

  defp restore_env(name, value) do
    original = System.get_env(name)
    if value, do: System.put_env(name, value), else: System.delete_env(name)

    on_exit(fn ->
      if original, do: System.put_env(name, original), else: System.delete_env(name)
    end)
  end

  defp json(data),
    do: %Tesla.Env{
      status: 200,
      headers: [{"content-type", "application/json"}],
      body: Jason.encode!(data)
    }

  # #5 is in another repo, so commits are fetched from two repos, in the order their issues come
  defp issue_search_page(order) do
    search_page(
      [
        issue(1, "COMPLETED", []),
        issue(2, "NOT_PLANNED", []),
        issue(3, "DUPLICATE", []),
        issue(4, "COMPLETED", ["wontfix"]),
        issue(5, "COMPLETED", [])
        |> Map.merge(%{
          "closedAt" => "2026-10-05T12:00:00Z",
          "repository" => %{"name" => "bonfire_common"}
        })
      ],
      order
    )
  end

  # #10 has a commit in the window, #20 has none
  defp open_issue_search_page(order) do
    search_page(
      [
        issue(10, nil, []) |> Map.merge(%{"closedAt" => nil, "title" => "Search filters"}),
        issue(20, nil, []) |> Map.put("closedAt", nil)
      ],
      order
    )
  end

  defp search_page(issues, order) do
    put_in(@empty_search, ["data", "search", "edges"], order.(Enum.map(issues, &%{"node" => &1})))
    |> put_in(["data", "search", "issueCount"], length(issues))
  end

  defp issue(number, state_reason, labels) do
    %{
      "number" => number,
      "closedAt" => "2026-10-15T12:00:00Z",
      "stateReason" => state_reason,
      "title" => "Issue #{number}",
      "url" => "https://github.com/bonfire-networks/bonfire-app/issues/#{number}",
      "repository" => %{"name" => "bonfire-app"},
      "author" => %{"login" => "someone"},
      "issueType" => nil,
      "milestone" => nil,
      "labels" => %{
        "edges" => Enum.map(labels, &%{"node" => %{"name" => &1, "color" => "ffffff"}})
      },
      "assignees" => %{"edges" => []},
      "comments" => %{"edges" => []}
    }
  end

  # each repo has one commit for #10, the one in bonfire_common older
  defp commit_history(body, order) do
    nodes =
      cond do
        String.contains?(body, ~s(name: \\"bonfire-app\\")) ->
          [commit("bonfire-app", "aaaaaaa1234567890", "2026-10-20T12:00:00Z")]

        String.contains?(body, ~s(name: \\"bonfire_common\\")) ->
          [commit("bonfire_common", "bbbbbbb1234567890", "2026-10-06T12:00:00Z")]

        true ->
          []
      end
      |> order.()

    %{
      "data" => %{
        "repository" => %{
          "defaultBranchRef" => %{
            "target" => %{
              "history" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => nodes
              }
            }
          }
        }
      }
    }
  end

  defp commit(repo, oid, date) do
    %{
      "oid" => oid,
      "committedDate" => date,
      "message" => "Add search filters #10",
      "url" => "https://github.com/bonfire-networks/#{repo}/commit/#{oid}",
      "author" => %{"user" => %{"login" => "someone"}}
    }
  end

  defp open_issue_batch do
    %{
      "data" => %{
        "issue0" => %{
          "issue" => %{
            "number" => 10,
            "title" => "Search filters",
            "url" => "https://github.com/bonfire-networks/bonfire-app/issues/10",
            "state" => "OPEN",
            "author" => %{"login" => "someone"},
            "labels" => %{"edges" => []}
          }
        }
      }
    }
  end
end
