defmodule Bonfire.Common.TriggerCI do
  @moduledoc """
  WIP: A module for triggering CI/CD rebuilds across different providers.
  Requires explicit provider specification for reliable operation.

  ## Provider Compatibility

  ### GitHub Actions
  Requires adding `repository_dispatch` trigger to your workflow:

      name: Deploy
      on:
        push:
          branches: [main]
        repository_dispatch:    # Add this line
          types: [push]         # Add this line

  ### Gitea Actions
  Similar to GitHub Actions - requires adding `repository_dispatch` trigger.

  ### Drone CI
  Works with existing `.drone.yml` files without modification.
  Triggers a new build on the specified branch.

  ### GitLab CI
  Works with existing `.gitlab-ci.yml` files without modification.
  Uses pipeline trigger API to simulate a push event.


  ## Examples

      # GitHub 
      trigger_rebuild(:github, "mayel", "my-website", "ghp_token123")
      #=> {:ok, %{provider: :github, method: :repository_dispatch, status: :success}}

      # GitLab 
      trigger_rebuild(:gitlab, "mayel", "my-site", "glpat-token123")
      #=> {:ok, %{provider: :gitlab, method: :pipeline_trigger, status: :success, response: %{...}}}

      # GitLab - with a self-hosted instance
      trigger_rebuild(:gitlab, "gitlab.project.org", "mayel", "my-site", "glpat-token123")

      # Drone - works with any Drone instance
      trigger_rebuild(:drone, "drone.project.org", "mayel", "api", "drone_token123")
      #=> {:ok, %{provider: :drone, method: :build_trigger, status: :success, response: %{...}}}

      # Gitea - works with any Gitea instance  
      trigger_rebuild(:gitea, "git.project.org", "mayel", "project", "gitea_token123")
      #=> {:ok, %{provider: :gitea, method: :repository_dispatch, status: :success}}


  ## Setup Instructions

  ### Gitea
  1. Create a Personal Access Token
  2. Add `repository_dispatch: types: [push]` to your workflow triggers  
  3. Use the token with TriggerCI

  ### GitHub
  1. Create a Personal Access Token with `repo` scope
  2. Add `repository_dispatch: types: [push]` to your workflow triggers
  3. Use the token with TriggerCI

  ### GitLab  
  1. Go to Project Settings > CI/CD > Pipeline triggers
  2. Create a new trigger token
  3. Use the token with TriggerCI (works immediately with existing pipelines)

  ### Drone
  1. Create a user token in your Drone settings
  2. Use the token with TriggerCI (works immediately with existing pipelines)

  """

  import Untangle
  use Bonfire.Common.Config

  @type provider :: :github | :gitlab | :drone | :gitea
  @type repo_info :: %{
          host: String.t(),
          owner: String.t(),
          name: String.t(),
          provider: provider()
        }

  @type trigger_options :: Keyword.t()

  @default_options [
    branch: "main",
    event_type: "push",
    workflow_id: nil,
    variables: %{},
    reason: "Triggered from Elixir app at #{DateTime.utc_now() |> DateTime.to_iso8601()}"
  ]

  def req_options(), do: Config.get([:bonfire_posts, :req_options], [])

  @doc """
  Triggers a CI rebuild with explicit provider specification.

  ## Parameters

    - `provider` - CI provider atom (`:github`, `:gitlab`, `:drone`, `:gitea`)
    - `host` - Git host (e.g., "github.com", "gitlab.example.com", "drone.company.com")
    - `owner` - Repository owner/organization
    - `repo_name` - Repository name
    - `token` - Authentication token for the CI provider
    - `options` - Optional keyword list with configuration (see `t:trigger_options/0`)

  ## Examples

      iex> trigger_rebuild(:github, "github.com", "mayel", "test", "token")
      {:ok, %{provider: :github, method: :repository_dispatch, status: :success}}

      iex> trigger_rebuild(:gitlab, "gitlab.com", "mayel", "test", "token", branch: "develop")
      {:ok, %{provider: :gitlab, method: :pipeline_trigger, status: :success, response: %{}}}

      iex> trigger_rebuild(:unknown, "example.com", "owner", "repo", "token")
      {:error, "Unsupported provider: unknown"}

  """
  @spec trigger_rebuild(
          provider(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          trigger_options()
        ) :: {:ok, any()} | {:error, any()}
  def trigger_rebuild(provider, host \\ nil, owner, repo_name, token, options \\ [])

  def trigger_rebuild(:github, nil, owner, repo_name, token, options) do
    trigger_rebuild(:github, "github.com", owner, repo_name, token, options)
  end

  def trigger_rebuild(:gitlab, nil, owner, repo_name, token, options) do
    trigger_rebuild(:gitlab, "gitlab.com", owner, repo_name, token, options)
  end

  def trigger_rebuild(provider, owner, repo_name, token, options, _) when is_list(options) do
    trigger_rebuild(provider, nil, owner, repo_name, token, options)
  end

  def trigger_rebuild(provider, host, owner, repo_name, token, options) do
    repo_info = %{
      host: normalize_host(host),
      owner: owner,
      name: repo_name,
      provider: provider
    }

    merged_options = Keyword.merge(@default_options, options)
    do_trigger_rebuild(provider, repo_info, token, merged_options)
  end

  # Provider-specific trigger functions

  defp do_trigger_rebuild(:github, repo_info, token, options) do
    case options[:workflow_id] do
      nil -> trigger_repository_dispatch(:github, repo_info, token, options)
      workflow_id -> trigger_workflow_dispatch(:github, repo_info, token, workflow_id, options)
    end
  end

  defp do_trigger_rebuild(:gitea, repo_info, token, options) do
    case options[:workflow_id] do
      nil -> trigger_repository_dispatch(:gitea, repo_info, token, options)
      workflow_id -> trigger_workflow_dispatch(:gitea, repo_info, token, workflow_id, options)
    end
  end

  defp do_trigger_rebuild(:gitlab, repo_info, token, options) do
    project_identifier =
      URI.encode("#{repo_info.owner}/#{repo_info.name}", &URI.char_unreserved?/1)

    url = build_api_url(:gitlab, repo_info, "/projects/#{project_identifier}/trigger/pipeline")

    # GitLab uses form-encoded data for pipeline triggers
    form_data = %{
      token: token,
      ref: options[:branch]
    }

    # Add variables
    variables =
      options[:variables]
      |> Map.put("REBUILD_REASON", options[:reason])
      |> Map.put("TRIGGERED_BY", "elixir_app")
      |> Map.put("TRIGGER_TIMESTAMP", DateTime.utc_now() |> DateTime.to_iso8601())
      |> Enum.reduce(form_data, fn {key, value}, acc ->
        Map.put(acc, "variables[#{key}]", to_string(value))
      end)

    info("Triggering GitLab pipeline for #{repo_info.owner}/#{repo_info.name}")

    case Req.post(url, Keyword.merge([form: variables], req_options())) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, %{provider: :gitlab, method: :pipeline_trigger, status: :success, response: body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitLab API returned #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "HTTP request failed: #{Exception.message(exception)}"}
    end
  end

  defp do_trigger_rebuild(:drone, repo_info, token, options) do
    url = build_api_url(:drone, repo_info, "/repos/#{repo_info.owner}/#{repo_info.name}/builds")

    headers = [authorization: "Bearer #{token}"]

    payload = %{
      branch: options[:branch],
      message: options[:reason]
    }

    info("Triggering Drone build for #{repo_info.owner}/#{repo_info.name}")

    case Req.post(url, Keyword.merge([json: payload, headers: headers], req_options())) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{provider: :drone, method: :build_trigger, status: :success, response: body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Drone API returned #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "HTTP request failed: #{Exception.message(exception)}"}
    end
  end

  defp do_trigger_rebuild(provider, _repo_info, _token, _options) do
    {:error, "Unsupported provider: #{provider}"}
  end

  # Common trigger methods for GitHub-style providers

  defp trigger_repository_dispatch(provider, repo_info, token, options) do
    url =
      build_api_url(provider, repo_info, "/repos/#{repo_info.owner}/#{repo_info.name}/dispatches")

    headers = build_auth_headers(provider, token)

    # Simulate a push event with additional context
    payload = %{
      # Default is "push"
      event_type: options[:event_type],
      client_payload:
        Map.merge(options[:variables], %{
          branch: options[:branch],
          reason: options[:reason],
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          triggered_by: "elixir_app",
          # Simulate push event data structure
          ref: "refs/heads/#{options[:branch]}",
          repository: %{
            name: repo_info.name,
            full_name: "#{repo_info.owner}/#{repo_info.name}",
            default_branch: options[:branch]
          },
          pusher: %{
            name: "ci-trigger",
            email: "ci-trigger@#{repo_info.host}"
          }
        })
    }

    info(
      "Triggering #{provider} repository dispatch (#{options[:event_type]}) for #{repo_info.owner}/#{repo_info.name}"
    )

    case Req.post(url, Keyword.merge([json: payload, headers: headers], req_options())) do
      {:ok, %{status: status}} when status in [200, 204] ->
        {:ok, %{provider: provider, method: :repository_dispatch, status: :success}}

      {:ok, %{status: status, body: body}} ->
        {:error,
         "#{String.capitalize(to_string(provider))} API returned #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "HTTP request failed: #{Exception.message(exception)}"}
    end
  end

  defp trigger_workflow_dispatch(provider, repo_info, token, workflow_id, options) do
    url =
      build_api_url(
        provider,
        repo_info,
        "/repos/#{repo_info.owner}/#{repo_info.name}/actions/workflows/#{workflow_id}/dispatches"
      )

    headers = build_auth_headers(provider, token)

    payload = %{
      ref: options[:branch],
      inputs:
        Map.merge(options[:variables], %{
          reason: options[:reason],
          triggered_by: "elixir_app",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })
    }

    info("Triggering #{provider} workflow dispatch for #{repo_info.owner}/#{repo_info.name}")

    case Req.post(url, Keyword.merge([json: payload, headers: headers], req_options())) do
      {:ok, %{status: status}} when status in [200, 204] ->
        {:ok, %{provider: provider, method: :workflow_dispatch, status: :success}}

      {:ok, %{status: status, body: body}} ->
        {:error,
         "#{String.capitalize(to_string(provider))} API returned #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "HTTP request failed: #{Exception.message(exception)}"}
    end
  end

  # Common helper functions

  defp build_api_url(:github, repo_info, path) do
    base_url =
      case repo_info.host do
        "github.com" -> "https://api.github.com"
        # GitHub Enterprise
        _ -> "https://#{repo_info.host}/api/v3"
      end

    "#{base_url}#{path}"
  end

  defp build_api_url(:gitlab, repo_info, path) do
    protocol =
      if String.contains?(repo_info.host, "localhost") or
           String.contains?(repo_info.host, "127.0.0.1"),
         do: "http",
         else: "https"

    "#{protocol}://#{repo_info.host}/api/v4#{path}"
  end

  defp build_api_url(:drone, repo_info, path) do
    protocol =
      if String.contains?(repo_info.host, "localhost") or
           String.contains?(repo_info.host, "127.0.0.1"),
         do: "http",
         else: "https"

    "#{protocol}://#{repo_info.host}/api#{path}"
  end

  defp build_api_url(:gitea, repo_info, path) do
    protocol =
      if String.contains?(repo_info.host, "localhost") or
           String.contains?(repo_info.host, "127.0.0.1"),
         do: "http",
         else: "https"

    "#{protocol}://#{repo_info.host}/api/v1#{path}"
  end

  defp build_auth_headers(:github, token) do
    [
      authorization: "token #{token}",
      accept: "application/vnd.github.v3+json",
      user_agent: "ElixirTriggerCI/1.0"
    ]
  end

  defp build_auth_headers(:gitea, token) do
    [authorization: "token #{token}"]
  end

  defp normalize_host(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/\/$/, "")
  end

  defp extract_repo_info(path) do
    case String.split(String.trim(path, "/"), "/") do
      [owner, repo_name | _] when owner != "" and repo_name != "" ->
        # Remove .git suffix if present
        clean_repo_name = String.replace_suffix(repo_name, ".git", "")
        {:ok, {owner, clean_repo_name}}

      _ ->
        {:error, "Invalid repository path: #{path}"}
    end
  end
end
