# if Bonfire.Common.Extend.module_enabled?(Versioce.Changelog.DataGrabber) do
defmodule Bonfire.Common.Changelog.Github.DataGrabber do
  @moduledoc """
  Datagrabber for changelog generation, `Versioce.Config.Changelog.datagrabber/0`

  Uses repository history to obtain and format data.
  """
  @behaviour Versioce.Changelog.DataGrabber

  import Untangle
  use Bonfire.Common.E
  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  # alias Versioce.Changelog.Sections
  alias Versioce.Changelog.Anchors
  alias Versioce.Changelog.DataGrabber.Version
  alias Versioce.Config

  @impl Versioce.Changelog.DataGrabber
  def get_versions(unreleased_to \\ "HEAD") do
    issues = fetch_issues()

    anchors =
      struct!(Anchors, %{
        added: ["✨", "💡", "👷", "✅"],
        changed: ["🚀", "💅", "🎨", "📝", "🌏", "⚡", "🚧"],
        deprecated: ["♻️"],
        removed: ["⚰️"],
        fixed: ["🐛"],
        security: ["🚨", "🔒"]
      })

    version = prepare_version_data(issues, unreleased_to, anchors)
    {:ok, [version]}
  end

  @impl Versioce.Changelog.DataGrabber
  def get_version(version \\ "HEAD") do
    issues = fetch_issues()

    anchors =
      struct!(Anchors, %{
        added: ["✨", "💡", "👷", "✅"],
        changed: ["🚀", "💅", "🎨", "📝", "🌏", "⚡", "🚧"],
        deprecated: ["♻️"],
        removed: ["⚰️"],
        fixed: ["🐛"],
        security: ["🚨", "🔒"]
      })

    version_struct = prepare_version_data(issues, version, anchors)
    {:ok, version_struct}
  end

  defp prepare_version_data(issues, version, anchors) do
    sections = prepare_sections(issues, anchors)

    debug(sections, "Prepared sections")
    debug(Map.keys(sections), "Section keys found")

    # Create organized messages with proper ordering 
    all_messages =
      sections
      |> Enum.sort_by(fn {section, _messages} ->
        # Define the order we want sections to appear
        section_order = %{
          added: 1,
          changed: 2,
          deprecated: 3,
          removed: 4,
          fixed: 5,
          security: 6,
          # Put "other" at the end
          other: 99
        }

        Map.get(section_order, section, 50)
      end)
      |> Enum.flat_map(fn {_section, messages} -> messages end)

    debug(length(all_messages), "Total messages for Versioce")

    # Create commit group structure that Versioce expects - this is the key!
    commit_group = %{
      version: version,
      messages: all_messages
    }

    debug(commit_group, "Commit group structure")

    # Use Versioce's make_version function to create proper Version struct
    version_struct = Version.make_version(commit_group, anchors)

    debug(version_struct, "Final version struct from Versioce")

    version_struct
  end

  def get_first_changelog_date() do
    # should be running from root, use relative path
    changelog_path = "docs/CHANGELOG.md"

    with {:ok, content} <- File.read(changelog_path) do
      # Regex to match date in format (YYYY-M-D), allowing single or double digit month/day
      case Regex.run(~r/\((\d{4}-\d{1,2}-\d{1,2})\)/, content, capture: :all_but_first) do
        [date_str] -> date_str
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  # Normalizes a date string to "YYYY-MM-DD" format.
  # Accepts Date structs or strings like "2025-10-2", "2025-1-9", "2025-10-02".
  # Returns nil if input is nil or invalid.
  @doc """
  Normalize a date string or Date struct to "YYYY-MM-DD".

      iex> Bonfire.Common.Changelog.Github.DataGrabber.normalize_date("2025-10-2")
      "2025-10-02"

      iex> Bonfire.Common.Changelog.Github.DataGrabber.normalize_date("2025-1-9")
      "2025-01-09"

      iex> Bonfire.Common.Changelog.Github.DataGrabber.normalize_date("2025-10-02")
      "2025-10-02"

      iex> Bonfire.Common.Changelog.Github.DataGrabber.normalize_date(~D[2025-10-2])
      "2025-10-02"

      iex> Bonfire.Common.Changelog.Github.DataGrabber.normalize_date(nil)
      nil
  """
  def normalize_date(nil), do: nil
  def normalize_date(%Date{} = date), do: Date.to_iso8601(date)

  def normalize_date(date_str) when is_binary(date_str) do
    # Accepts "YYYY-M-D", "YYYY-MM-DD", etc.
    case Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})$/, String.trim(date_str)) do
      [_, y, m, d] ->
        ymd = "#{y}-#{String.pad_leading(m, 2, "0")}-#{String.pad_leading(d, 2, "0")}"

        if ymd != date_str do
          require Logger
          Logger.debug("Normalized date '#{date_str}' to '#{ymd}'")
        end

        ymd

      _ ->
        # Try to parse as Date
        case Date.from_iso8601(date_str) do
          {:ok, date} -> Date.to_iso8601(date)
          _ -> nil
        end
    end
  end

  @doc """
  Filters a list of items (issues, PRs, or commits) to only include those with a relevant date field
  (closedAt, mergedAt, etc) within the given date window. Items without a date field are always included.
  Raises if any out-of-range items are found (for debugging).

  The date field checked is, in order:
    - "closedAt", "closed_at"
    - "mergedAt", "merged_at"
    - "matched_issue_closed_at"
    - "matched_issue.mergedAt", "matched_issue.merged_at"
    - "matched_issue.closedAt", "matched_issue.closed_at"

  ## Examples

      iex> items = [
      ...>   %{"number" => 1, "closedAt" => "2025-10-10T12:00:00Z"},
      ...>   %{"number" => 2, "mergedAt" => "2025-10-15T12:00:00Z"},
      ...>   %{"number" => 3, "closedAt" => "2024-01-01T12:00:00Z"}
      ...> ]
      iex> Bonfire.Common.Changelog.Github.DataGrabber.filter_items_by_date!(items, "2025-10-01", "2025-10-31")
      [%{"number" => 1, "closedAt" => "2025-10-10T12:00:00Z"}, %{"number" => 2, "mergedAt" => "2025-10-15T12:00:00Z"}]
  """
  def filter_items_by_date!(items, after_date, before_date) do
    {in_range, out_of_range} = do_filter_items_by_date(items, after_date, before_date)

    if out_of_range != [] do
      require Logger

      Logger.error("""
      Out-of-range issues/PRs/items detected!
      After: #{inspect(after_date)}, Before: #{inspect(before_date)}
      Offending items:
      #{inspect(Enum.map(out_of_range, fn item -> %{number: e(item, "number", nil) || e(item, "matched_issue_number", nil), closed_at: item_closed_date(item)} end),
      pretty: true)}
      """)

      raise "Out-of-range issues/PRs/items detected! See logs for details."
    end

    in_range
  end

  def filter_items_by_date(items, after_date, before_date) do
    {in_range, out_of_range} = do_filter_items_by_date(items, after_date, before_date)

    if out_of_range != [] do
      require Logger

      Logger.error("""
      Out-of-range issues/PRs/items detected!
      After: #{inspect(after_date)}, Before: #{inspect(before_date)}
      Offending items:
      #{inspect(Enum.map(out_of_range, fn item -> %{number: e(item, "number", nil) || e(item, "matched_issue_number", nil), closed_at: item_closed_date(item)} end),
      pretty: true)}
      """)
    end

    in_range
  end

  defp do_filter_items_by_date(items, after_date, before_date) do
    Enum.split_with(items, fn item ->
      date_str = item_closed_date(item)

      if is_nil(date_str) do
        true
      else
        case Date.from_iso8601(String.slice(date_str, 0, 10)) do
          {:ok, date} ->
            after_ok =
              case after_date do
                nil -> true
                _ -> Date.compare(date, Date.from_iso8601!(after_date)) != :lt
              end

            before_ok =
              case before_date do
                nil -> true
                _ -> Date.compare(date, Date.from_iso8601!(before_date)) != :gt
              end

            after_ok and before_ok

          _ ->
            true
        end
      end
    end)
  end

  defp item_closed_date(item) do
    e(item, "closedAt", nil) ||
      e(item, "closed_at", nil) ||
      e(item, "matched_issue_closed_at", nil) ||
      e(item, "matched_issue", "closedAt", nil) ||
      e(item, "matched_issue", "closed_at", nil) ||
      e(item, "matched_issue_merged_at", nil) ||
      e(item, "matched_issue", "mergedAt", nil) ||
      e(item, "matched_issue", "merged_at", nil) ||
      e(item, "mergedAt", nil) ||
      e(item, "merged_at", nil)
  end

  def fetch_issues(opts \\ []) do
    # Ensure Finch is started
    Bonfire.Common.HTTP.ensure_ready()

    # pick HTTP client 
    Neuron.Config.set(connection_module: Bonfire.Common.HTTP)

    org = Keyword.get(opts, :org, "bonfire-networks")

    closed_after_raw =
      Keyword.get(opts, :closed_after) ||
        System.get_env("CHANGES_CLOSED_AFTER") || get_first_changelog_date() ||
        Date.add(Date.utc_today(), -Keyword.get(opts, :closed_in_last_days, 30))

    closed_before_raw =
      Keyword.get(opts, :closed_before) ||
        System.get_env("CHANGES_CLOSED_BEFORE")

    closed_after = normalize_date(closed_after_raw)
    closed_before = normalize_date(closed_before_raw)

    debug(closed_after, "Normalized closed_after")
    debug(closed_before, "Normalized closed_before")

    # Fetch issues first
    issues =
      fetch_github_issues(org, closed_after, closed_before)

    # |> filter_items_by_date(closed_after, closed_before)

    # Get all commits and PRs that reference these issues
    issue_numbers = Enum.map(issues, &e(&1, "number", nil)) |> Enum.filter(&(&1 != nil))

    # Fetch PRs that reference issues and add them to the PR contributors
    issues_with_pr_contributors =
      add_pr_contributors_to_issues(org, issues, issue_numbers)
      |> filter_items_by_date(closed_after, closed_before)

    # Fetch unreferenced PRs (those not linked to issues)
    referenced_prs = get_referenced_pr_numbers(issues_with_pr_contributors)

    unreferenced_prs =
      fetch_unreferenced_prs(org, closed_after, closed_before, referenced_prs)
      |> filter_items_by_date(closed_after, closed_before)

    # Fetch unreferenced commits (those not linked to issues/PRs)
    referenced_commits = prepare_referenced_commit_shas(issues_with_pr_contributors)

    # Get repository list from issues for commit fetching
    repo_list = get_repository_list(issues_with_pr_contributors)

    unreferenced_commits =
      fetch_unreferenced_commits(
        org,
        closed_after,
        closed_before,
        referenced_commits,
        repo_list,
        issues_with_pr_contributors
      )
      |> filter_items_by_date(closed_after, closed_before)

    debug(length(issues_with_pr_contributors), "Issues fetched")
    debug(length(unreferenced_prs), "Unreferenced PRs fetched")
    debug(length(unreferenced_commits), "Unreferenced commits fetched")

    issues_with_pr_contributors ++ unreferenced_prs ++ unreferenced_commits
  end

  defp fetch_github_issues(org, closed_after, closed_before \\ nil) do
    # Use explicit issue type in query with pagination
    query_string =
      "org:#{org} is:issue state:closed closed:>#{closed_after}" <>
        if closed_before, do: " closed:<#{closed_before}", else: ""

    debug(query_string, "GitHub Issues Query (with closed_before)")

    fetch_github_issues_paginated(query_string, nil, [])
  end

  defp fetch_github_issues_paginated(query_string, cursor, accumulated_issues) do
    cursor_param = if cursor, do: ", after: \"#{cursor}\"", else: ""

    with token when is_binary(token) and token != "" <-
           System.get_env("GITHUB_TOKEN") || {:error, "missing GITHUB_TOKEN in env"},
         {:ok, %{body: body}} <-
           Neuron.query(
             """
             query {
               search(first: 50, type: ISSUE, query: "#{query_string}"#{cursor_param}) {
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
                       closedAt
                       title
                       url
                       # bodyText
                       repository {
                         name
                       }
                       author {
                         login
                       }
                       issueType {
                         name
                       }
                       milestone {
                         title
                       }
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
                       comments(last: 100) {
                         edges {
                           node {
                             author {
                               login
                             }
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
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      case (is_binary(body) and Jason.decode(body)) || {:ok, body} do
        {:ok, parsed_body} ->
          total_count = e(parsed_body, "data", "search", "issueCount", 0)
          raw_issues = e(parsed_body, "data", "search", "edges", [])
          page_info = e(parsed_body, "data", "search", "pageInfo", %{})
          has_next_page = e(page_info, "hasNextPage", false)
          end_cursor = e(page_info, "endCursor", nil)

          debug(
            %{
              total_count: total_count,
              page_size: length(raw_issues),
              has_next_page: has_next_page,
              accumulated_so_far: length(accumulated_issues),
              cursor: cursor
            },
            "GitHub Issues pagination info"
          )

          # Process current page
          current_page_issues =
            raw_issues
            |> Enum.map(&e(&1, "node", &1))
            # Mark as issue
            |> Enum.map(&Map.put(&1, "type", "issue"))
            # Filter out automated items
            |> Enum.reject(&is_automated_item?/1)

          all_issues = accumulated_issues ++ current_page_issues

          # Decide whether to continue pagination
          # Reasonable upper limit to avoid runaway pagination
          should_continue =
            has_next_page &&
              end_cursor &&
              length(all_issues) < 500

          if should_continue do
            debug(
              %{
                continuing: true,
                next_cursor: end_cursor,
                total_accumulated: length(all_issues)
              },
              "Continuing pagination for issues"
            )

            fetch_github_issues_paginated(query_string, end_cursor, all_issues)
          else
            debug(
              %{
                stopping: true,
                reason:
                  cond do
                    !has_next_page ->
                      "no more pages (#{length(raw_issues)})"

                    !end_cursor ->
                      "no cursor"

                    length(all_issues) >= 1000 ->
                      "hit safety limit (#{length(all_issues)} >= 1000)"

                    true ->
                      "unknown"
                  end,
                final_count: length(all_issues)
              },
              "Stopping pagination for issues"
            )

            all_issues
          end

        {:error, error} ->
          debug(error, "Failed to parse JSON response")
          accumulated_issues
      end
    else
      e ->
        debug(e, "Error fetching issues")
        accumulated_issues
    end
  end

  defp add_pr_contributors_to_issues(org, issues, issue_numbers) do
    # Use GitHub resource API to get timeline connections for each issue
    issues
    |> Enum.map(fn issue ->
      issue_number = e(issue, "number", nil)
      repo_name = e(issue, "repository", "name", "")

      # Get connected PRs and commits for this specific issue
      connected_prs_and_commits = fetch_connected_prs_for_issue(org, repo_name, issue_number)

      # Extract from unified timeline query
      connected_prs = connected_prs_and_commits[:prs] || []
      connected_commits = connected_prs_and_commits[:commits] || []

      # Extract contributors from connected PRs and commits
      pr_contributors =
        connected_prs
        |> Enum.flat_map(&get_pr_contributors/1)

      commit_contributors =
        connected_commits
        |> Enum.map(&e(&1, "author", "user", "login", nil))
        |> Enum.filter(&(&1 != nil))

      additional_contributors =
        (pr_contributors ++ commit_contributors)
        |> Enum.uniq()
        |> Enum.reject(&is_bot?/1)

      debug(length(connected_prs), "Connected PRs for issue ##{issue_number}")
      debug(length(connected_commits), "Connected commits for issue ##{issue_number}")

      if length(connected_prs) > 0 do
        debug(
          connected_prs |> Enum.map(&e(&1, "number", nil)),
          "PR numbers found for issue ##{issue_number}"
        )
      end

      # Store additional contributors in the issue
      issue
      |> Map.put("pr_contributors", additional_contributors)
      |> Map.put("referenced_prs", connected_prs |> Enum.map(&e(&1, "number", nil)))
    end)
  end

  defp fetch_connected_prs_for_issue(org, repo_name, issue_number) do
    issue_url = "https://github.com/#{org}/#{repo_name}/issues/#{issue_number}"

    debug(
      %{
        issue_url: issue_url,
        org: org,
        repo: repo_name,
        issue: issue_number
      },
      "Fetching connected PRs for issue"
    )

    with token when is_binary(token) and token != "" <-
           System.get_env("GITHUB_TOKEN") || {:error, "missing GITHUB_TOKEN in env"},
         {:ok, %{body: body}} <-
           Neuron.query(
             """
             query {
               resource(url: "#{issue_url}") {
                 ... on Issue {
                   timelineItems(itemTypes: [CONNECTED_EVENT, DISCONNECTED_EVENT, CROSS_REFERENCED_EVENT, CLOSED_EVENT, REFERENCED_EVENT], first: 50) {
                     nodes {
                       ... on ConnectedEvent {
                         subject {
                           ... on PullRequest {
                             number
                             title
                             url
                             author {
                               login
                             }
                             commits(first: 10) {
                               edges {
                                 node {
                                   commit {
                                     author {
                                       user {
                                         login
                                       }
                                     }
                                   }
                                 }
                               }
                             }
                           }
                         }
                       }
                       ... on DisconnectedEvent {
                         subject {
                           ... on PullRequest {
                             number
                             title
                             url
                             author {
                               login
                             }
                             commits(first: 10) {
                               edges {
                                 node {
                                   commit {
                                     author {
                                       user {
                                         login
                                       }
                                     }
                                   }
                                 }
                               }
                             }
                           }
                         }
                       }
                       ... on CrossReferencedEvent {
                         source {
                           ... on PullRequest {
                             number
                             title
                             url
                             author {
                               login
                             }
                             commits(first: 10) {
                               edges {
                                 node {
                                   commit {
                                     author {
                                       user {
                                         login
                                       }
                                     }
                                   }
                                 }
                               }
                             }
                           }
                         }
                       }
                       ... on ReferencedEvent {
                         commit {
                           oid
                           message
                           url
                           author {
                             user {
                               login
                             }
                           }
                         }
                       }
                       ... on ClosedEvent {
                         closer {
                           ... on PullRequest {
                             number
                             title
                             url
                             author {
                               login
                             }
                             commits(first: 10) {
                               edges {
                                 node {
                                   commit {
                                     author {
                                       user {
                                         login
                                       }
                                     }
                                   }
                                 }
                               }
                             }
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
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      case (is_binary(body) and Jason.decode(body)) || {:ok, body} do
        {:ok, parsed_body} ->
          debug(parsed_body, "Timeline response for issue ##{issue_number}")

          timeline_nodes = e(parsed_body, "data", "resource", "timelineItems", "nodes", [])
          debug(length(timeline_nodes), "Timeline nodes found for issue ##{issue_number}")

          {prs, commits} =
            timeline_nodes
            |> Enum.reduce({[], []}, fn node, {acc_prs, acc_commits} ->
              # Extract PRs and commits from different event types
              items = []

              # ConnectedEvent
              connected_item = e(node, "subject", nil)

              connected_items =
                if connected_item &&
                     (Map.has_key?(connected_item, "number") ||
                        Map.has_key?(connected_item, "oid")),
                   do: [connected_item],
                   else: []

              # DisconnectedEvent
              disconnected_item = e(node, "subject", nil)

              disconnected_items =
                if disconnected_item &&
                     (Map.has_key?(disconnected_item, "number") ||
                        Map.has_key?(disconnected_item, "oid")),
                   do: [disconnected_item],
                   else: []

              # CrossReferencedEvent
              cross_ref_source = e(node, "source", nil)

              cross_ref_items =
                if cross_ref_source &&
                     (Map.has_key?(cross_ref_source, "number") ||
                        Map.has_key?(cross_ref_source, "oid")),
                   do: [cross_ref_source],
                   else: []

              # ReferencedEvent (commits)
              referenced_commit = e(node, "commit", nil)

              referenced_commits =
                if referenced_commit && Map.has_key?(referenced_commit, "oid"),
                  do: [referenced_commit],
                  else: []

              # ClosedEvent
              closer = e(node, "closer", nil)

              closer_items =
                if closer && (Map.has_key?(closer, "number") || Map.has_key?(closer, "oid")),
                  do: [closer],
                  else: []

              all_items =
                items ++
                  connected_items ++
                  disconnected_items ++ cross_ref_items ++ referenced_commits ++ closer_items

              # Separate PRs and commits
              node_prs = all_items |> Enum.filter(&Map.has_key?(&1, "number"))
              node_commits = all_items |> Enum.filter(&Map.has_key?(&1, "oid"))

              debug(
                %{
                  node_prs: length(node_prs),
                  node_commits: length(node_commits),
                  total: length(all_items)
                },
                "Items found in timeline node for issue ##{issue_number}"
              )

              {acc_prs ++ node_prs, acc_commits ++ node_commits}
            end)

          filtered_prs =
            prs |> Enum.reject(&is_automated_item?/1) |> Enum.uniq_by(&e(&1, "number", nil))

          filtered_commits = commits |> Enum.uniq_by(&e(&1, "oid", nil))

          debug(
            %{
              total_prs: length(filtered_prs),
              total_commits: length(filtered_commits)
            },
            "Final counts for issue ##{issue_number}"
          )

          %{prs: filtered_prs, commits: filtered_commits}

        {:error, error} ->
          debug(error, "Failed to parse timeline JSON for issue ##{issue_number}")
          %{prs: [], commits: []}
      end
    else
      e ->
        debug(e, "Error fetching timeline for issue ##{issue_number}")
        %{prs: [], commits: []}
    end
  end

  defp get_pr_contributors(pr) do
    # Get PR author
    author = e(pr, "author", "login", nil)

    # Get commit authors from PR
    commit_authors =
      e(pr, "commits", "edges", [])
      |> Enum.map(fn commit_edge ->
        e(commit_edge, "node", "commit", "author", "user", "login", nil)
      end)
      |> Enum.filter(&(&1 != nil))

    [author | commit_authors]
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  defp fetch_unreferenced_prs(org, closed_after, closed_before, referenced_pr_numbers) do
    # Fetch all merged PRs and filter out referenced ones
    all_prs = fetch_all_merged_prs(org, closed_after, closed_before)
    debug(length(all_prs), "Total PRs fetched from GitHub")
    debug(referenced_pr_numbers, "Referenced PR numbers to exclude")

    unreferenced =
      all_prs
      |> Enum.reject(fn pr -> e(pr, "number", nil) in referenced_pr_numbers end)
      # Mark as PR
      |> Enum.map(&Map.put(&1, "type", "pr"))

    debug(length(unreferenced), "Unreferenced PRs after filtering")

    # Debug a few sample PRs
    if length(unreferenced) > 0 do
      sample_pr = List.first(unreferenced)

      debug(
        %{
          number: e(sample_pr, "number", nil),
          title: e(sample_pr, "title", ""),
          type: e(sample_pr, "type", ""),
          author: e(sample_pr, "author", "login", "")
        },
        "Sample unreferenced PR"
      )
    end

    unreferenced
  end

  defp fetch_unreferenced_commits(
         org,
         committed_after,
         committed_before,
         referenced_commit_shas,
         repo_list,
         issues
       ) do
    # Fetch recent commits from all repositories found in issues and filter out referenced ones
    all_commits = fetch_all_recent_commits(org, committed_after, committed_before, repo_list)
    debug(length(all_commits), "Total commits fetched from GitHub")
    debug(length(referenced_commit_shas), "Referenced commit SHAs to exclude")

    all_commits
    |> Enum.reject(fn commit -> e(commit, "oid", nil) in referenced_commit_shas end)
    |> Enum.reject(&is_automated_commit?/1)
    |> Enum.reject(&is_merge_commit?/1)
    |> merge_similar_commits()
    |> try_match_commits_to_issues(issues)
    |> Enum.map(&Map.put(&1, "type", "commit"))
  end

  defp get_repository_list(issues) do
    # Extract unique repository names from issues
    repos =
      issues
      |> Enum.map(&e(&1, "repository", "name", nil))
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()

    # Always include bonfire-app as fallback
    unique_repos = (repos ++ ["bonfire-app"]) |> Enum.uniq()

    debug(unique_repos, "Repository list for commit fetching")
    unique_repos
  end

  defp fetch_all_recent_commits(org, committed_after, committed_before, repo_list) do
    # Fetch commits from all discovered repositories
    repo_list
    |> Enum.flat_map(fn repo_name ->
      fetch_commits_from_repo(org, repo_name, committed_after, committed_before)
    end)
    |> Enum.uniq_by(&e(&1, "oid", nil))
  end

  defp fetch_commits_from_repo(org, repo_name, committed_after, committed_before \\ nil) do
    fetch_commits_from_repo_paginated(org, repo_name, committed_after, committed_before, nil, [])
  end

  defp fetch_commits_from_repo_paginated(
         org,
         repo_name,
         committed_after,
         committed_before,
         cursor,
         accumulated_commits
       ) do
    cursor_param = if cursor, do: ", after: \"#{cursor}\"", else: ""
    since_param = "since: \"#{committed_after}T00:00:00Z\""

    until_param =
      if committed_before,
        do: ", until: \"#{committed_before}T23:59:59Z\"",
        else: ""

    with token when is_binary(token) and token != "" <-
           System.get_env("GITHUB_TOKEN") || {:error, "missing GITHUB_TOKEN in env"},
         {:ok, %{body: body}} <-
           Neuron.query(
             """
             query {
               repository(owner: "#{org}", name: "#{repo_name}") {
                 defaultBranchRef {
                   target {
                     ... on Commit {
                       history(first: 50, #{since_param}#{until_param}#{cursor_param}) {
                         pageInfo {
                           hasNextPage
                           endCursor
                         }
                         nodes {
                           oid
                           message
                           url
                           author {
                             user {
                               login
                             }
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
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      case (is_binary(body) and Jason.decode(body)) || {:ok, body} do
        {:ok, parsed_body} ->
          history =
            e(parsed_body, "data", "repository", "defaultBranchRef", "target", "history", %{})

          commits = e(history, "nodes", [])
          page_info = e(history, "pageInfo", %{})
          has_next_page = e(page_info, "hasNextPage", false)
          end_cursor = e(page_info, "endCursor", nil)

          debug(
            %{
              repo: repo_name,
              page_size: length(commits),
              has_next_page: has_next_page,
              accumulated_so_far: length(accumulated_commits),
              cursor: cursor
            },
            "GitHub Commits pagination info"
          )

          # Filter current page
          filtered_commits =
            commits
            |> Enum.reject(&is_automated_commit?/1)
            |> Enum.reject(&is_merge_commit?/1)

          all_commits = accumulated_commits ++ filtered_commits

          # Decide whether to continue pagination
          # Reasonable upper limit for commits per repo
          should_continue =
            has_next_page &&
              end_cursor &&
              length(all_commits) < 2000

          if should_continue do
            debug(
              %{
                continuing: true,
                next_cursor: end_cursor,
                total_accumulated: length(all_commits),
                repo: repo_name
              },
              "Continuing pagination for commits"
            )

            fetch_commits_from_repo_paginated(
              org,
              repo_name,
              committed_after,
              committed_before,
              end_cursor,
              all_commits
            )
          else
            debug(
              %{
                stopping: true,
                reason:
                  cond do
                    !has_next_page ->
                      "no more pages (#{length(commits)})"

                    !end_cursor ->
                      "no cursor"

                    length(all_commits) >= 2000 ->
                      "hit safety limit (#{length(all_commits)} >= 2000)"

                    true ->
                      "unknown"
                  end,
                final_count: length(all_commits),
                repo: repo_name
              },
              "Stopping pagination for commits"
            )

            all_commits
          end

        {:error, error} ->
          debug(error, "Failed to parse commits JSON response for #{repo_name}")
          accumulated_commits
      end
    else
      e ->
        debug(e, "Error fetching commits from #{repo_name}")
        accumulated_commits
    end
  end

  # Filter out automated commits and generic ones
  defp is_automated_commit?(commit) do
    message = e(commit, "message", "")
    author = e(commit, "author", "user", "login", "")

    # Get first line (title) of commit message
    title = message |> String.split("\n") |> List.first() |> String.trim() |> String.downcase()

    # Filter out generic commit titles
    is_bot?(author) or
      String.starts_with?(message, "Bump ") or
      String.starts_with?(message, "Update ") or
      String.contains?(String.downcase(message), "dependabot") or
      String.contains?(String.downcase(message), "release") or
      String.contains?(String.downcase(message), "automated") or
      title in [
        "up",
        "rel",
        "release",
        "ci",
        "log",
        "clean",
        "f",
        "d",
        "locales",
        "misc",
        "icons",
        "changelog",
        "tools",
        "changelog [skip ci]"
      ] or
      String.starts_with?(title, "rc") or
      (String.starts_with?(title, "v") and String.contains?(title, ".")) or
      String.match?(title, ~r/^rc?\d+\.\d+/) or
      String.match?(title, ~r/^v\d+\.\d+/)
  end

  defp merge_similar_commits(commits) do
    # Group commits by their title (first line of message)
    commits
    |> Enum.group_by(fn commit ->
      message = e(commit, "message", "")
      message |> String.split("\n") |> List.first() |> String.trim()
    end)
    |> Enum.map(fn {title, commit_group} ->
      case commit_group do
        [single_commit] ->
          # Single commit, return as-is
          single_commit

        multiple_commits ->
          # Multiple commits with same title - merge them
          first_commit = List.first(multiple_commits)

          # Collect all commit SHAs and URLs
          all_shas = multiple_commits |> Enum.map(&e(&1, "oid", "")) |> Enum.filter(&(&1 != ""))
          all_urls = multiple_commits |> Enum.map(&e(&1, "url", "")) |> Enum.filter(&(&1 != ""))

          # Collect all unique authors
          all_authors =
            multiple_commits
            |> Enum.map(&e(&1, "author", "user", "login", nil))
            |> Enum.filter(&(&1 != nil))
            |> Enum.uniq()

          # Create merged commit with multiple SHAs and authors
          first_commit
          |> Map.put("merged_shas", all_shas)
          |> Map.put("merged_urls", all_urls)
          |> Map.put("merged_authors", all_authors)
          |> Map.put("is_merged", true)
      end
    end)
  end

  defp try_match_commits_to_issues(commits, issues) do
    # Create a lookup map of issue numbers to issues for fast matching
    issue_lookup =
      issues
      |> Enum.reduce(%{}, fn issue, acc ->
        issue_number = e(issue, "number", nil)
        if issue_number, do: Map.put(acc, issue_number, issue), else: acc
      end)

    # Get set of existing issue numbers for quick lookup
    existing_issue_numbers = MapSet.new(Map.keys(issue_lookup))

    # Collect all referenced issue numbers that we need to fetch
    missing_issue_numbers =
      commits
      |> Enum.flat_map(fn commit ->
        message = e(commit, "message", "")
        extract_github_issue_references(message)
      end)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(existing_issue_numbers, &1))

    # Fetch missing issues if any
    fetched_issues =
      if length(missing_issue_numbers) > 0 do
        debug(missing_issue_numbers, "Fetching missing issues referenced in commits")
        fetch_issues_by_numbers(missing_issue_numbers)
      else
        []
      end

    # Add fetched issues to our lookup
    enhanced_issue_lookup =
      fetched_issues
      |> Enum.reduce(issue_lookup, fn issue, acc ->
        issue_number = e(issue, "number", nil)
        if issue_number, do: Map.put(acc, issue_number, issue), else: acc
      end)

    # Updated set of all known issue numbers
    all_known_issue_numbers = MapSet.new(Map.keys(enhanced_issue_lookup))

    commits
    |> Enum.reduce([], fn commit, acc ->
      message = e(commit, "message", "")

      # Extract GitHub issue URLs and numbers from commit message
      issue_numbers = extract_github_issue_references(message)

      # Try to find matching issues (now including fetched ones)
      matched_issues =
        issue_numbers
        |> Enum.map(&Map.get(enhanced_issue_lookup, &1))
        |> Enum.filter(&(&1 != nil))

      if length(matched_issues) > 0 do
        # Found matching issues - check if any are already included in main list
        # Use first match
        matched_issue = List.first(matched_issues)
        issue_number = e(matched_issue, "number", nil)

        if MapSet.member?(existing_issue_numbers, issue_number) do
          # Issue is already included in main list - skip this commit
          debug(
            %{
              commit_sha: String.slice(e(commit, "oid", ""), 0, 7),
              matched_issue: issue_number,
              action: "skipped - issue already in main list"
            },
            "Commit references existing issue"
          )

          # Don't include this commit
          acc
        else
          # Issue was fetched or not in our main list - include commit with issue info
          issue_title = e(matched_issue, "title", "")
          was_fetched = issue_number in missing_issue_numbers

          debug(
            %{
              commit_sha: String.slice(e(commit, "oid", ""), 0, 7),
              matched_issue: issue_number,
              issue_title: String.slice(issue_title, 0, 50),
              action:
                if(was_fetched,
                  do: "included - issue fetched",
                  else: "included - issue not in main list"
                )
            },
            "Matched commit to issue"
          )

          # Extract contributors from the matched issue
          issue_author = e(matched_issue, "author", "login", nil)

          issue_contributors =
            [issue_author]
            |> Enum.filter(&(&1 != nil))
            |> Enum.reject(&is_bot?/1)

          enhanced_commit =
            commit
            |> Map.put("matched_issue_number", issue_number)
            |> Map.put("matched_issue_title", issue_title)
            |> Map.put("matched_issue_url", e(matched_issue, "url", ""))
            |> Map.put("matched_issue_contributors", issue_contributors)
            |> Map.put("was_fetched", was_fetched)
            # Track issue state
            |> Map.put("matched_issue_state", e(matched_issue, "state", "CLOSED"))

          [enhanced_commit | acc]
        end
      else
        # No matching issues - include commit as-is
        [commit | acc]
      end
    end)
    # Maintain original order
    |> Enum.reverse()
  end

  defp fetch_issues_by_numbers(issue_numbers) do
    # Batch fetch specific issues by their numbers
    # We'll use the repository context from the first commit if available
    # Could be made configurable
    org = "bonfire-networks"
    # Could be made dynamic
    repo = "bonfire-app"

    issue_numbers
    # Process in batches to avoid overwhelming the API
    |> Enum.chunk_every(20)
    |> Enum.flat_map(fn batch ->
      fetch_issue_batch(org, repo, batch)
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp fetch_issue_batch(org, repo, issue_numbers) do
    issue_queries =
      issue_numbers
      |> Enum.with_index()
      |> Enum.map(fn {issue_number, index} ->
        """
        issue#{index}: repository(owner: "#{org}", name: "#{repo}") {
          issue(number: #{issue_number}) {
            number
            title
            url
            state
            author {
              login
            }
            labels(first: 20) {
              edges {
                node {
                  name
                }
              }
            }
          }
        }
        """
      end)
      |> Enum.join("\n")

    query = """
    query {
      #{issue_queries}
    }
    """

    with token when is_binary(token) and token != "" <-
           System.get_env("GITHUB_TOKEN") || {:error, "missing GITHUB_TOKEN in env"},
         {:ok, %{body: body}} <-
           Neuron.query(
             query,
             nil,
             url: "https://api.github.com/graphql",
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      case (is_binary(body) and Jason.decode(body)) || {:ok, body} do
        {:ok, parsed_body} ->
          data = e(parsed_body, "data", %{})

          issue_numbers
          |> Enum.with_index()
          |> Enum.map(fn {issue_number, index} ->
            issue_data = e(data, "issue#{index}", "issue", nil)

            if issue_data do
              debug(
                %{
                  number: issue_number,
                  title: e(issue_data, "title", "") |> String.slice(0, 50),
                  state: e(issue_data, "state", "")
                },
                "Fetched missing issue"
              )

              # Transform to match our expected format
              issue_data
              |> Map.put("repository", %{"name" => repo})
              |> Map.put("type", "issue")
            else
              debug(issue_number, "Failed to fetch missing issue")
              nil
            end
          end)
          |> Enum.filter(&(&1 != nil))

        {:error, error} ->
          debug(error, "Failed to parse batch issue fetch response")
          []
      end
    else
      e ->
        debug(e, "Error fetching issue batch")
        []
    end
  end

  defp extract_github_issue_references(text) do
    # Patterns to match GitHub issue references in commit messages
    patterns = [
      # Full GitHub URLs: https://github.com/org/repo/issues/123
      ~r/github\.com\/[\w\-\.]+\/[\w\-\.]+\/issues\/(\d+)/i,
      # Simple #number patterns at start of message or after whitespace
      ~r/(?:^|\s)#(\d+)(?:\s|$)/,
      # "fixes #123", "closes #456" patterns
      ~r/(?:fix(?:es)?|close(?:s|d)?|resolve(?:s|d)?)\s*#(\d+)/i,
      # Issue URLs in any position
      ~r/\/issues\/(\d+)/
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(fn num_str ->
        case Integer.parse(num_str) do
          {num, ""} -> num
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
    end)
    |> Enum.uniq()
  end

  # Filter out merge commits
  defp is_merge_commit?(commit) do
    message = e(commit, "message", "")

    String.starts_with?(message, "Merge ") or
      String.contains?(message, "Merge pull request") or
      String.contains?(message, "Merge branch")
  end

  defp get_referenced_pr_numbers(issues) do
    issues
    |> Enum.flat_map(fn issue ->
      title = e(issue, "title", "")
      body = e(issue, "bodyText", "")

      # Extract PR numbers from title and body using regex
      text = "#{title} #{body}"
      extract_pr_numbers_from_text(text)
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  defp extract_pr_numbers_from_text(text) do
    # Match patterns like: #123, PR #123, Pull Request #123, github.com/org/repo/pull/123, /issues/123
    pr_patterns = [
      ~r/(?:PR|pr|pull request|Pull Request)\s*#(\d+)/i,
      ~r/github\.com\/[\w\-\.]+\/[\w\-\.]+\/pull\/(\d+)/,
      # Relative URL
      ~r/\/pull\/(\d+)/,
      ~r/(?:closes?|close|closed|fixes?|fix|fixed|resolves?|resolve|resolved)\s+#(\d+)/i,
      ~r/(?:closes?|close|closed|fixes?|fix|fixed|resolves?|resolve|resolved)\s+.*\/issues\/(\d+)/i,
      # URL pattern for issues
      ~r/\/issues\/(\d+)/,
      # Simple #number pattern
      ~r/#(\d+)/
    ]

    pr_patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)
    end)
    |> Enum.uniq()
  rescue
    _ -> []
  end

  defp prepare_referenced_commit_shas(issues) do
    issues
    |> Enum.flat_map(fn issue ->
      title = e(issue, "title", "")
      body = e(issue, "bodyText", "")

      # Extract commit SHAs from title and body using regex
      text = "#{title} #{body}"
      extract_commit_shas_from_text(text)
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  defp extract_commit_shas_from_text(text) do
    # Match commit SHA patterns (7-40 hex characters)
    commit_patterns = [
      ~r/github\.com\/[\w\-\.]+\/[\w\-\.]+\/commit\/([a-f0-9]{7,40})/i,
      ~r/(?:commit|sha)\s*:?\s*([a-f0-9]{7,40})/i,
      # Standalone hex strings (might catch some false positives)
      ~r/\b([a-f0-9]{7,40})\b/
    ]

    commit_patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, text, capture: :all_but_first)
      |> List.flatten()
      # Only SHAs 7+ chars
      |> Enum.filter(&(String.length(&1) >= 7))
    end)
    |> Enum.uniq()
  rescue
    _ -> []
  end

  defp fetch_all_merged_prs(org, merged_after, merged_before \\ nil) do
    query_string =
      "org:#{org} type:pr is:merged merged:>#{merged_after}" <>
        if merged_before, do: " merged:<#{merged_before}", else: ""

    debug(query_string, "GitHub PRs Query (with merged_before)")

    fetch_all_merged_prs_paginated(query_string, nil, [])
  end

  defp fetch_all_merged_prs_paginated(query_string, cursor, accumulated_prs) do
    cursor_param = if cursor, do: ", after: \"#{cursor}\"", else: ""

    with token when is_binary(token) and token != "" <-
           System.get_env("GITHUB_TOKEN") || {:error, "missing GITHUB_TOKEN in env"},
         {:ok, %{body: body}} <-
           Neuron.query(
             """
             query {
               search(first: 50, type: ISSUE, query: "#{query_string}"#{cursor_param}) {
                 issueCount
                 pageInfo {
                   hasNextPage
                   endCursor
                 }
                 edges {
                   node {
                     ... on PullRequest {
                       number
                       title
                       url
                       mergedAt
                       author {
                         login
                       }
                       milestone {
                         title
                       }
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
                       commits(first: 10) {
                         edges {
                           node {
                             commit {
                               author {
                                 user {
                                   login
                                 }
                               }
                             }
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
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      case (is_binary(body) and Jason.decode(body)) || {:ok, body} do
        {:ok, parsed_body} ->
          total_count = e(parsed_body, "data", "search", "issueCount", 0)
          raw_prs = e(parsed_body, "data", "search", "edges", [])
          page_info = e(parsed_body, "data", "search", "pageInfo", %{})
          has_next_page = e(page_info, "hasNextPage", false)
          end_cursor = e(page_info, "endCursor", nil)

          debug(
            %{
              total_count: total_count,
              page_size: length(raw_prs),
              has_next_page: has_next_page,
              accumulated_so_far: length(accumulated_prs),
              cursor: cursor
            },
            "GitHub PRs pagination info"
          )

          # Process current page
          current_page_prs =
            raw_prs
            |> Enum.map(&e(&1, "node", &1))
            # Filter out automated items
            |> Enum.reject(&is_automated_item?/1)

          all_prs = accumulated_prs ++ current_page_prs

          # Decide whether to continue pagination
          # Reasonable upper limit for PRs
          should_continue =
            has_next_page &&
              end_cursor &&
              length(all_prs) < 500

          if should_continue do
            debug(
              %{
                continuing: true,
                next_cursor: end_cursor,
                total_accumulated: length(all_prs)
              },
              "Continuing pagination for PRs"
            )

            fetch_all_merged_prs_paginated(query_string, end_cursor, all_prs)
          else
            debug(
              %{
                stopping: true,
                reason:
                  cond do
                    !has_next_page -> "no more pages (#{length(raw_prs)})"
                    !end_cursor -> "no cursor"
                    length(all_prs) >= 500 -> "hit safety limit (#{length(all_prs)} >= 500)"
                    true -> "unknown"
                  end,
                final_count: length(all_prs)
              },
              "Stopping pagination for PRs"
            )

            all_prs
          end

        {:error, error} ->
          debug(error, "Failed to parse PR JSON response")
          accumulated_prs
      end
    else
      e ->
        debug(e, "Error fetching PRs")
        accumulated_prs
    end
  end

  defp prepare_sections(issues, anchors) do
    do_prepare_sections(issues, anchors, %{})
  end

  defp do_prepare_sections([], _anchors, acc), do: acc

  defp do_prepare_sections([item | tail], anchors, acc) do
    labels =
      e(item, "labels", "edges", [])
      |> Enum.map(&e(&1, "node", "name", nil))
      |> Enums.filter_empty([])

    issue_type = e(item, "issueType", "name", nil)
    milestone = e(item, "milestone", "title", nil)
    title = e(item, "title", "")
    item_type = e(item, "type", "issue")

    # Debug each item being processed
    debug(
      %{
        title: title,
        number: e(item, "number", nil),
        type: item_type,
        issue_type: issue_type,
        milestone: milestone,
        labels: labels
      },
      "Processing item for sections"
    )

    # Use issue type, milestone, and labels for better categorization
    grouping_texts = categorize_item(issue_type, labels, title, item_type, milestone, item)

    # Debug the grouping_texts result
    debug(
      %{
        item_number: e(item, "number", nil),
        item_type: item_type,
        computed_grouping_texts: grouping_texts
      },
      "Computed grouping texts for item"
    )

    do_prepare_sections(
      tail,
      anchors,
      add_to_section(item, grouping_texts, anchors, acc)
    )
  end

  # Categorize items (issues and PRs) based on milestones, GitHub issue types, labels, and title patterns
  defp categorize_item(issue_type, labels, title, item_type, milestone, item) do
    # Check if this is a commit referencing an open issue
    matched_issue_state = e(item, "matched_issue_state", nil)
    is_work_in_progress = matched_issue_state && matched_issue_state != "CLOSED"

    # Process strings once - handle empty titles for commits
    actual_title =
      case {item_type, title} do
        {"commit", ""} ->
          # For commits with empty titles, try to get the commit message
          message = e(item, "message", "")

          if message != "" do
            message |> String.split("\n") |> List.first() |> String.trim()
          else
            ""
          end

        _ ->
          title
      end

    title_lower = String.downcase(actual_title)
    milestone_lower = milestone && String.downcase(milestone)
    issue_type_lower = issue_type && String.downcase(issue_type)

    # Create label set for O(1) lookups
    label_set = MapSet.new(labels)

    # Debug the categorization process
    debug(
      %{
        title: title,
        actual_title: actual_title,
        title_lower: title_lower,
        issue_type: issue_type,
        issue_type_lower: issue_type_lower,
        item_type: item_type,
        milestone: milestone,
        milestone_lower: milestone_lower,
        labels: labels,
        matched_issue_state: matched_issue_state,
        is_work_in_progress: is_work_in_progress
      },
      "Categorizing item"
    )

    result =
      cond do
        # Work in progress takes precedence - commit references open issue
        is_work_in_progress ->
          debug("matched: work in progress", "categorization_match")
          ["🚧"]

        # GitHub native issue types (should match before title-based)
        issue_type_lower == "bug" ->
          debug("matched: issue_type bug", "categorization_match")
          ["🐛"]

        issue_type_lower in ["feature", "enhancement"] ->
          debug("matched: issue_type feature/enhancement", "categorization_match")
          ["✨"]

        issue_type_lower in ["task", "improvement", "documentation", "docs"] ->
          debug("matched: issue_type task/improvement/docs", "categorization_match")
          ["🚀"]

        # Label-based categorization (O(1) lookups) - now returns emojis directly
        by_label = categorize_by_labels(label_set) ->
          by_label
          |> debug("label_result")

        # Title-based or Milestone-based patterns using pattern matching
        true ->
          categorize_by_title(title_lower, item_type, label_set) |> debug("title_result") ||
            (milestone_lower &&
               categorize_by_milestone(milestone_lower) |> debug("milestone_result"))
      end || ["📝"]

    debug(
      %{
        item_number: e(item, "number", nil),
        item_type: item_type,
        final_result: result
      },
      "Final categorization result"
    )

    result
  end

  # Milestone categorization helper - now returns emojis
  defp categorize_by_milestone(milestone_lower) when is_binary(milestone_lower) do
    cond do
      String.contains?(milestone_lower, "feature") ->
        ["✨"]

      String.contains?(milestone_lower, "bug") or String.contains?(milestone_lower, "fix") ->
        ["🐛"]

      String.contains?(milestone_lower, "improvement") ->
        ["🚀"]

      String.contains?(milestone_lower, "security") ->
        ["🚨"]

      String.contains?(milestone_lower, "breaking") ->
        ["⚰️"]

      String.contains?(milestone_lower, "deprecat") ->
        ["♻️"]

      # Release milestones go to Other
      String.contains?(milestone_lower, "release") ->
        ["📝"]

      true ->
        false
    end
  end

  defp categorize_by_milestone(_) do
    false
  end

  # Label categorization helper using MapSet for O(1) lookups - now returns emojis directly
  defp categorize_by_labels(label_set) do
    cond do
      # Security & Safety (maps to security section)
      MapSet.member?(label_set, "Security") or
        MapSet.member?(label_set, "Abuse Mitigation") or
          MapSet.member?(label_set, "Compliance") ->
        ["🚨"]

      # Features & Enhancements (maps to added section)
      MapSet.member?(label_set, "Feature") or
        MapSet.member?(label_set, "enhancement") or
        MapSet.member?(label_set, "1st Priority") or
        MapSet.member?(label_set, "2nd Priority") or
          MapSet.member?(label_set, "Good first issue") ->
        ["✨"]

      # UI/UX specific improvements
      MapSet.member?(label_set, "UI/UX") ->
        ["💅"]

      # Performance & Optimization
      MapSet.member?(label_set, "Performance") or
          MapSet.member?(label_set, "opptimisation") ->
        ["⚡"]

      # Accessibility
      MapSet.member?(label_set, "Accessibility") ->
        ["👶"]

      # Federation & ActivityPub
      MapSet.member?(label_set, "ActivityPub") or
          MapSet.member?(label_set, "Needs Federation Testing") ->
        ["🌏"]

      # Config & Settings
      MapSet.member?(label_set, "Config / Settings") ->
        ["🔧"]

      # Developer Experience & Modularity
      MapSet.member?(label_set, "Developer Experience") or
        MapSet.member?(label_set, "Extensiblity / Modularity") or
          MapSet.member?(label_set, "Progressive Enhancement") ->
        ["👷"]

      # Testing
      MapSet.member?(label_set, "Testing") or
        MapSet.member?(label_set, "Has unit test") or
        MapSet.member?(label_set, "Needs unit test") or
          MapSet.member?(label_set, "Needs manual testing") ->
        ["✅"]

      # Documentation
      MapSet.member?(label_set, "Documentation") or
          MapSet.member?(label_set, "documentation") ->
        ["📝"]

      # Database & Core
      MapSet.member?(label_set, "Database") or
          MapSet.member?(label_set, "Core") ->
        ["🗄️"]

      # Dependencies & External
      MapSet.member?(label_set, "dependencies") or
          MapSet.member?(label_set, "github_actions") ->
        ["📦"]

      # Languages
      MapSet.member?(label_set, "Elixir") ->
        ["💜"]

      MapSet.member?(label_set, "JS") ->
        ["💛"]

      # Bug fixes (maps to fixed section)
      MapSet.member?(label_set, "Bug") or
          MapSet.member?(label_set, "bug") ->
        ["🐛"]

      # Deprecated items
      MapSet.member?(label_set, "[DEP]") or
          MapSet.member?(label_set, "Deprecated") ->
        ["♻️"]

      # Removed/Breaking changes
      MapSet.member?(label_set, "[REM]") or
        MapSet.member?(label_set, "Breaking Change") or
          MapSet.member?(label_set, "Canceled") ->
        ["⚰️"]

      # Reliability & Scalability
      MapSet.member?(label_set, "Reliability") or
        MapSet.member?(label_set, "Scalability") or
          MapSet.member?(label_set, "Resource Use") ->
        ["🔧"]

      # Care work & Community
      MapSet.member?(label_set, "Care work") ->
        ["❤️"]

      # Specific features by area
      MapSet.member?(label_set, "Feed") ->
        ["📰"]

      MapSet.member?(label_set, "Search") ->
        ["🔍"]

      MapSet.member?(label_set, "Moderation") ->
        ["🛡️"]

      MapSet.member?(label_set, "Discussion") ->
        ["💬"]

      # Work in progress states
      MapSet.member?(label_set, "Help needed") or
        MapSet.member?(label_set, "help wanted") or
        MapSet.member?(label_set, "In Progress") or
        MapSet.member?(label_set, "Todo") or
        MapSet.member?(label_set, "Beta Feedback") or
        MapSet.member?(label_set, "Blocked") or
          MapSet.member?(label_set, "Contains multiple todos") ->
        ["🚧"]

      # General improvements (catch-all for Improvement and Refactor)
      MapSet.member?(label_set, "Improvement") or
          MapSet.member?(label_set, "Refactor") ->
        ["🚀"]

      # Org-wide enhancement/feature labels
      MapSet.member?(label_set, "good first issue") ->
        ["✨"]

      true ->
        false
    end
  end

  # Title categorization using pattern matching where possible - now returns emojis
  defp categorize_by_title(title_lower, item_type, label_set) do
    case title_lower do
      # Direct pattern matching for common prefixes
      "bug" <> _ ->
        ["🐛"]

      "bug:" <> _ ->
        ["🐛"]

      "fix " <> _ ->
        ["🐛"]

      "fixes " <> _ ->
        ["🐛"]

      "fixed " <> _ ->
        ["🐛"]

      "add " <> _ ->
        ["✨"]

      "create " <> _ ->
        ["✨"]

      "implement " <> _ ->
        ["✨"]

      "update " <> _ ->
        ["🚀"]

      "bump " <> _ ->
        ["📦"]

      "improve " <> _ ->
        ["🚀"]

      "remove " <> _ ->
        ["⚰️"]

      "delete " <> _ ->
        ["⚰️"]

      "deprecate " <> _ ->
        ["♻️"]

      # Fallback to contains checks for complex patterns
      _ ->
        cond do
          # Bug patterns
          String.starts_with?(title_lower, "bug: ") -> ["🐛"]
          String.contains?(title_lower, "bug:") -> ["🐛"]
          String.contains?(title_lower, " bug ") -> ["🐛"]
          String.contains?(title_lower, "error") -> ["🐛"]
          String.contains?(title_lower, "issue") -> ["🐛"]
          String.contains?(title_lower, "problem") -> ["🐛"]
          String.contains?(title_lower, "doesn't work") -> ["🐛"]
          String.contains?(title_lower, "not working") -> ["🐛"]
          String.contains?(title_lower, "broken") -> ["🐛"]
          String.contains?(title_lower, "fails") -> ["🐛"]
          String.contains?(title_lower, "missing") -> ["🐛"]
          String.contains?(title_lower, "can't") -> ["🐛"]
          String.contains?(title_lower, "cannot") -> ["🐛"]
          # Feature patterns
          String.contains?(title_lower, "add ") -> ["✨"]
          String.contains?(title_lower, "new ") -> ["✨"]
          String.contains?(title_lower, "enable") -> ["✨"]
          String.contains?(title_lower, "support") -> ["✨"]
          String.contains?(title_lower, "allow") -> ["✨"]
          String.contains?(title_lower, "let users") -> ["✨"]
          # UI/UX patterns
          String.contains?(title_lower, "ui") -> ["💅"]
          String.contains?(title_lower, "tooltip") -> ["💅"]
          String.contains?(title_lower, "preview") -> ["💅"]
          String.contains?(title_lower, "display") -> ["💅"]
          String.contains?(title_lower, "show") -> ["💅"]
          # Performance patterns
          String.contains?(title_lower, "optimize") -> ["⚡"]
          String.contains?(title_lower, "performance") -> ["⚡"]
          String.contains?(title_lower, "speed") -> ["⚡"]
          # Testing patterns
          String.contains?(title_lower, "test") -> ["✅"]
          # Documentation patterns
          String.contains?(title_lower, "doc") -> ["📝"]
          # Security patterns
          String.contains?(title_lower, "security") -> ["🚨"]
          String.contains?(title_lower, "auth") -> ["🚨"]
          String.contains?(title_lower, "login") -> ["🚨"]
          String.contains?(title_lower, "permission") -> ["🚨"]
          # General improvement patterns
          String.contains?(title_lower, "better") -> ["🚀"]
          String.contains?(title_lower, "improve") -> ["🚀"]
          String.contains?(title_lower, "enhance") -> ["🚀"]
          String.contains?(title_lower, "update") -> ["🚀"]
          String.contains?(title_lower, "refactor") -> ["🚀"]
          String.contains?(title_lower, "make sure") -> ["🚀"]
          String.contains?(title_lower, "ensure") -> ["🚀"]
          String.contains?(title_lower, "check") -> ["🚀"]
          String.contains?(title_lower, "pagination") -> ["🚀"]
          String.contains?(title_lower, "handle") -> ["🚀"]
          # Default for PRs without other categorization
          item_type == "pr" and String.contains?(title_lower, "bump") -> ["📦"]
          # Default categorization
          true -> nil
        end
    end
  end

  # Default categorization helper
  defp default_categorization(label_set, item_type) do
    case {MapSet.size(label_set), item_type} do
      # PRs without labels default to improvements
      {0, "pr"} -> ["Improvement"]
      # Issues without labels go to other
      {0, _} -> ["Other"]
      # Use first label
      _ -> [Enum.at(MapSet.to_list(label_set), 0)]
    end
  end

  defp add_to_section(issue, grouping_texts, anchors, acc) do
    text = format_issue(issue)
    issue_number = e(issue, "number", nil)
    item_type = e(issue, "type", "issue")

    debug(
      %{
        number: issue_number,
        type: item_type,
        grouping_texts: grouping_texts,
        text_generated: text != nil,
        anchors_config: anchors |> Map.from_struct()
      },
      "Adding item to section"
    )

    if text do
      matched_section =
        anchors
        |> Map.from_struct()
        |> Enum.find_value(fn {section, anchor_strings} ->
          match_found =
            Enum.any?(anchor_strings, fn anchor ->
              # Debug each anchor comparison
              matches = anchor in grouping_texts

              if matches do
                debug(
                  %{
                    anchor: anchor,
                    grouping_texts: grouping_texts,
                    exact_match: true
                  },
                  "Anchor matched exactly"
                )
              end

              matches
            end)

          if match_found do
            debug(
              %{
                number: issue_number,
                type: item_type,
                section: section,
                matched_section: section,
                grouping_texts: grouping_texts,
                anchor_strings: anchor_strings
              },
              "Item matched section"
            )

            section
          else
            false
          end
        end)

      case matched_section do
        nil ->
          debug(
            %{
              number: issue_number,
              type: item_type,
              section: :other,
              grouping_texts: grouping_texts,
              available_anchors: anchors |> Map.from_struct() |> Map.values() |> List.flatten(),
              anchor_config: anchors |> Map.from_struct()
            },
            "Item went to OTHER section - no anchor match"
          )

          Map.update(acc, :other, [text], &([text] ++ &1))

        section ->
          debug(
            %{
              number: issue_number,
              type: item_type,
              section: section,
              matched_section: section,
              grouping_texts: grouping_texts
            },
            "Item successfully matched to section"
          )

          Map.update(acc, section, [text], &(&1 ++ [text]))
      end
    else
      debug(
        %{
          number: issue_number,
          type: item_type,
          reason: "no text generated"
        },
        "Item skipped"
      )

      acc
    end
  end

  def format_issue(item) do
    item_type = e(item, "type", "issue")

    case item_type do
      "commit" ->
        # Format commits differently
        message = e(item, "message", "")
        is_merged = e(item, "is_merged", false)
        matched_issue_number = e(item, "matched_issue_number", nil)
        matched_issue_title = e(item, "matched_issue_title", nil)
        matched_issue_url = e(item, "matched_issue_url", nil)

        # Take first line of commit message (title), but use issue title if matched
        title =
          if matched_issue_title && matched_issue_title != "" do
            matched_issue_title
          else
            message |> String.split("\n") |> List.first() |> String.trim()
          end

        # Get labels for display (from matched issue if available)
        labels =
          e(item, "labels", "edges", [])
          |> Enum.map(&e(&1, "node", "name", nil))
          |> Enum.filter(&(&1 != nil))

        # Get computed category for this item
        issue_type = e(item, "issueType", "name", nil)
        milestone = e(item, "milestone", "title", nil)
        computed_category = categorize_item(issue_type, labels, title, item_type, milestone, item)

        label_display = format_labels_for_display(labels, item_type, computed_category)

        if is_merged do
          # Handle merged commits with multiple SHAs
          merged_shas = e(item, "merged_shas", [])
          merged_urls = e(item, "merged_urls", [])
          merged_authors = e(item, "merged_authors", [])

          # Create links for each commit
          commit_links =
            Enum.zip(merged_shas, merged_urls)
            |> Enum.map(fn {sha, url} ->
              short_sha = String.slice(sha, 0, 7)
              "[`#{short_sha}`](#{url})"
            end)
            |> Enum.join(", ")

          # For commits that reference issues, get contributors from both commit and issue
          all_contributors =
            if matched_issue_number do
              # Get commit contributors
              commit_contributors =
                if length(merged_authors) > 0 do
                  merged_authors
                else
                  []
                end

              # Get issue contributors (if we have the referenced issue data)
              issue_contributors = get_referenced_issue_contributors(item)

              # Combine and deduplicate
              (commit_contributors ++ issue_contributors)
              |> Enum.uniq()
              |> Enum.reject(&is_bot?/1)
            else
              merged_authors |> Enum.reject(&is_bot?/1)
            end

          credits =
            if length(all_contributors) > 0 do
              " (thanks #{format_contributors(all_contributors)})"
            else
              ""
            end

          # Add issue link if matched
          issue_link =
            if matched_issue_number && matched_issue_url do
              " [##{matched_issue_number}](#{matched_issue_url})"
            else
              ""
            end

          "#{label_display}#{title}#{issue_link} #{commit_links}#{credits}"
        else
          # Handle single commit
          oid = e(item, "oid", "")
          url = e(item, "url", "")
          author = e(item, "author", "user", "login", "")

          short_oid = String.slice(oid, 0, 7)

          # For commits that reference issues, get contributors from both commit and issue
          all_contributors =
            if matched_issue_number do
              # Get commit author
              commit_contributors =
                if author && author != "" do
                  [author]
                else
                  []
                end

              # Get issue contributors (if we have the referenced issue data)
              issue_contributors = get_referenced_issue_contributors(item)

              # Combine and deduplicate
              (commit_contributors ++ issue_contributors)
              |> Enum.uniq()
              |> Enum.reject(&is_bot?/1)
            else
              if author && author != "" do
                [author] |> Enum.reject(&is_bot?/1)
              else
                []
              end
            end

          credits =
            if length(all_contributors) > 0 do
              " (thanks #{format_contributors(all_contributors)})"
            else
              ""
            end

          # Add issue link if matched
          issue_link =
            if matched_issue_number && matched_issue_url do
              " [##{matched_issue_number}](#{matched_issue_url})"
            else
              ""
            end

          "#{label_display}#{title}#{issue_link} [`#{short_oid}`](#{url})#{credits}"
        end

      _ ->
        # Handle issues and PRs as before
        case e(item, "title", nil) do
          title when is_binary(title) ->
            title = String.trim(title)
            number = e(item, "number", nil)
            url = e(item, "url", nil)

            # Get labels for display
            labels =
              e(item, "labels", "edges", [])
              |> Enum.map(&e(&1, "node", "name", nil))
              |> Enum.filter(&(&1 != nil))

            # Get computed category for this item
            issue_type = e(item, "issueType", "name", nil)
            milestone = e(item, "milestone", "title", nil)

            computed_category =
              categorize_item(issue_type, labels, title, item_type, milestone, item)

            label_display = format_labels_for_display(labels, item_type, computed_category)

            # Get all contributors
            contributors = get_contributors(item)

            # Get referenced PRs
            referenced_prs = e(item, "referenced_prs", [])

            credits =
              if length(contributors) > 0 do
                " (thanks #{format_contributors(contributors)})"
              else
                ""
              end

            # Add PR links if any
            pr_links =
              if length(referenced_prs) > 0 and item_type != "pr" do
                # Extract org and repo from the item URL to build correct PR URLs
                {org_name, repo_name} =
                  case e(item, "url", "") do
                    url when is_binary(url) and url != "" ->
                      # Parse URL like https://github.com/org/repo/issues/123
                      case String.split(url, "/") do
                        [_, _, "github.com", org, repo | _] -> {org, repo}
                        _ -> {"bonfire-networks", e(item, "repository", "name", "bonfire-app")}
                      end

                    _ ->
                      {"bonfire-networks", e(item, "repository", "name", "bonfire-app")}
                  end

                pr_list =
                  referenced_prs
                  |> Enum.filter(&(&1 != nil))
                  |> Enum.map(
                    &"[PR ##{&1}](https://github.com/#{org_name}/#{repo_name}/pull/#{&1})"
                  )
                  |> Enum.join(", ")

                if pr_list != "", do: " - #{pr_list}", else: ""
              else
                ""
              end

            # Format differently for PRs vs Issues
            case item_type do
              "pr" -> "#{label_display}#{title} [PR ##{number}](#{url})#{credits}"
              _ -> "#{label_display}#{title} [##{number}](#{url})#{pr_links}#{credits}"
            end

          _ ->
            nil
        end
    end
  end

  # Helper function to get contributors from referenced issue
  defp get_referenced_issue_contributors(commit_item) do
    # Check if this commit has matched issue contributor data stored
    matched_issue_contributors = e(commit_item, "matched_issue_contributors", [])

    if length(matched_issue_contributors) > 0 do
      debug(
        %{
          commit_oid: e(commit_item, "oid", nil),
          matched_issue: e(commit_item, "matched_issue_number", nil),
          issue_contributors: matched_issue_contributors
        },
        "Found issue contributors for commit"
      )

      matched_issue_contributors
    else
      debug(
        %{
          commit_oid: e(commit_item, "oid", nil),
          matched_issue: e(commit_item, "matched_issue_number", nil),
          note: "No issue contributors found"
        },
        "No issue contributors for commit"
      )

      []
    end
  end

  defp format_labels_for_display(labels, item_type, computed_category \\ nil) do
    # Since computed_category now contains emojis directly, just use the first one
    case computed_category do
      [emoji] when is_binary(emoji) ->
        "#{emoji} "

      _ ->
        ""
    end
  end

  defp get_contributors(issue) do
    # Get issue author
    author = e(issue, "author", "login", nil)

    # Get assignees
    assignees =
      e(issue, "assignees", "edges", [])
      |> Enum.map(&e(&1, "node", "login", nil))
      |> Enum.filter(&(&1 != nil))

    # Get commenters (unique)
    commenters =
      e(issue, "comments", "edges", [])
      |> Enum.map(&e(&1, "node", "author", "login", nil))
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()

    # Get PR contributors (from our cross-referencing)
    pr_contributors = e(issue, "pr_contributors", [])

    # Combine all contributors, remove duplicates, and exclude bots
    all_contributors =
      [author | assignees ++ commenters ++ pr_contributors]
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()
      |> Enum.reject(&is_bot?/1)

    all_contributors
  end

  defp format_contributors(contributors) do
    case length(contributors) do
      0 ->
        ""

      1 ->
        "@#{List.first(contributors)}"

      2 ->
        "@#{Enum.at(contributors, 0)} and @#{Enum.at(contributors, 1)}"

      n when n <= 5 ->
        {last, rest} = List.pop_at(contributors, -1)
        "#{Enum.map(rest, &"@#{&1}") |> Enum.join(", ")}, and @#{last}"

      _ ->
        # For more than 5 contributors, show first 3 and count
        first_three = Enum.take(contributors, 3)
        remaining_count = length(contributors) - 3
        "#{Enum.map(first_three, &"@#{&1}") |> Enum.join(", ")} and #{remaining_count} others"
    end
  end

  # Filter out known bots and automated accounts
  defp is_bot?(username) when is_binary(username) do
    String.ends_with?(username, "[bot]") or
      String.ends_with?(username, "-bot") or
      username in ["dependabot", "renovate", "github-actions", "codecov"]
  end

  defp is_bot?(_), do: false

  # Filter out automated items (issues/PRs) by author, title patterns, or exclusion labels
  defp is_automated_item?(item) do
    author = e(item, "author", "login", "")
    title = e(item, "title", "")

    labels =
      e(item, "labels", "edges", [])
      |> Enum.map(&e(&1, "node", "name", nil))
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(&String.downcase/1)

    is_bot?(author) or
      String.starts_with?(title, "Bump ") or
      (String.starts_with?(title, "Update ") and String.contains?(title, " to ")) or
      String.contains?(String.downcase(title), "dependabot") or
      String.contains?(String.downcase(title), "automated") or
      Enum.any?(labels, fn label ->
        # Exclude issues/PRs these labels
        label in ["duplicate", "wontfix"]
      end)
  end
end

# end
