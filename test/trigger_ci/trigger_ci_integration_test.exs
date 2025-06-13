defmodule Bonfire.Common.TriggerCIIntegrationTest do
  @moduledoc """
  Integration tests for TriggerCI with real HTTP calls.

  These tests are tagged as :integration and should only be run when:
  1. You have valid tokens for the services
  2. You want to test against real APIs
  3. You have test repositories set up

  Run with: `RUN_INTEGRATION_TESTS=true mix test --only integration`

  Environment variables needed:
  - GITHUB_TOKEN: GitHub personal access token
  - GITLAB_TOKEN: GitLab trigger token  
  - DRONE_TOKEN: Drone user token
  - GITEA_TOKEN: Gitea personal access token
  """

  use ExUnit.Case

  alias Bonfire.Common.TriggerCI

  @moduletag :integration

  # Test repository details - update these for your test repos
  @test_repos %{
                # github: %{host: "github.com", owner: "your-username", repo: "test-repo"},
                # gitlab: %{host: "gitlab.com", owner: "your-username", repo: "test-repo"},
                # drone: %{host: "drone.example.com", owner: "your-username", repo: "test-repo"},
                # gitea: %{host: "git.example.com", owner: "your-username", repo: "test-repo"}
              }

  describe "real API integration tests" do
    @tag :github
    test "triggers GitHub Actions via repository_dispatch" do
      token = System.get_env("GITHUB_TOKEN")
      repo = @test_repos[:github]

      if token && repo do
        result =
          TriggerCI.trigger_rebuild(
            :github,
            repo.host,
            repo.owner,
            repo.repo,
            token,
            event_type: "integration_test",
            reason: "Testing TriggerCI integration at #{DateTime.utc_now()}",
            variables: %{
              test_run: true,
              timestamp: DateTime.utc_now() |> DateTime.to_unix()
            }
          )

        assert {:ok, response} = result
        assert response.provider == :github
        assert response.method == :repository_dispatch
        assert response.status == :success

        IO.puts("✅ GitHub integration test successful")
      else
        IO.puts("⚠️  Skipping GitHub test - GITHUB_TOKEN not set or repo not configured")
      end
    end

    @tag :gitlab
    test "triggers GitLab CI pipeline" do
      token = System.get_env("GITLAB_TOKEN")
      repo = @test_repos[:gitlab]

      if token && repo do
        result =
          TriggerCI.trigger_rebuild(
            :gitlab,
            repo.host,
            repo.owner,
            repo.repo,
            token,
            branch: "main",
            reason: "Integration test from TriggerCI",
            variables: %{
              TEST_MODE: "true",
              TRIGGER_SOURCE: "elixir_integration_test"
            }
          )

        assert {:ok, response} = result
        assert response.provider == :gitlab
        assert response.method == :pipeline_trigger
        assert response.status == :success
        assert is_map(response.response)

        IO.puts("✅ GitLab integration test successful - Pipeline ID: #{response.response["id"]}")
      else
        IO.puts("⚠️  Skipping GitLab test - GITLAB_TOKEN not set or repo not configured")
      end
    end

    @tag :drone
    test "triggers Drone CI build" do
      token = System.get_env("DRONE_TOKEN")
      repo = @test_repos[:drone]

      if token && repo do
        result =
          TriggerCI.trigger_rebuild(
            :drone,
            repo.host,
            repo.owner,
            repo.repo,
            token,
            branch: "main",
            reason: "Drone integration test from TriggerCI module"
          )

        assert {:ok, response} = result
        assert response.provider == :drone
        assert response.method == :build_trigger
        assert response.status == :success
        assert is_map(response.response)

        IO.puts("✅ Drone integration test successful - Build ##{response.response["number"]}")
      else
        IO.puts("⚠️  Skipping Drone test - DRONE_TOKEN not set or repo not configured")
      end
    end

    @tag :gitea
    test "triggers Gitea Actions" do
      token = System.get_env("GITEA_TOKEN")
      repo = @test_repos[:gitea]

      if token && repo do
        result =
          TriggerCI.trigger_rebuild(
            :gitea,
            repo.host,
            repo.owner,
            repo.repo,
            token,
            event_type: "integration_test",
            branch: "main",
            reason: "Gitea Actions integration test",
            variables: %{
              integration_test: "true"
            }
          )

        assert {:ok, response} = result
        assert response.provider == :gitea
        assert response.method == :repository_dispatch
        assert response.status == :success

        IO.puts("✅ Gitea integration test successful")
      else
        IO.puts("⚠️  Skipping Gitea test - GITEA_TOKEN not set or repo not configured")
      end
    end
  end

  describe "error handling with real APIs" do
    @tag :error_handling
    test "handles invalid GitHub token gracefully" do
      repo = @test_repos[:github]

      if repo = repo[:repo] do
        result =
          TriggerCI.trigger_rebuild(
            :github,
            repo[:host],
            repo[:owner],
            repo,
            "invalid_token_12345",
            reason: "Testing error handling"
          )

        assert {:error, error_message} = result
        assert error_message =~ "GitHub API returned"
        assert error_message =~ "401"

        IO.puts("✅ GitHub error handling test successful")
      else
        IO.puts("⚠️  Skipping GitHub error test - repo not set")
      end
    end

    @tag :error_handling
    test "handles non-existent GitLab repository" do
      token = System.get_env("GITLAB_TOKEN")

      if token do
        result =
          TriggerCI.trigger_rebuild(
            :gitlab,
            "gitlab.com",
            "nonexistent-user-12345",
            "nonexistent-repo-67890",
            token
          )

        assert {:error, error_message} = result
        assert error_message =~ "GitLab API returned"

        IO.puts("✅ GitLab error handling test successful")
      else
        IO.puts("⚠️  Skipping GitLab error test - GITLAB_TOKEN not set")
      end
    end
  end

  describe "performance and reliability" do
    @tag :performance
    test "measures response times" do
      token = System.get_env("GITHUB_TOKEN")
      repo = @test_repos[:github]

      if token && repo do
        {time_microseconds, result} =
          :timer.tc(fn ->
            TriggerCI.trigger_rebuild(
              :github,
              repo.host,
              repo.owner,
              repo.repo,
              token,
              reason: "Performance test"
            )
          end)

        time_ms = time_microseconds / 1000

        assert {:ok, _response} = result
        assert time_ms < 5000, "Request took too long: #{time_ms}ms"

        IO.puts("✅ GitHub performance test: #{Float.round(time_ms, 2)}ms")
      else
        IO.puts("⚠️  Skipping performance test - GITHUB_TOKEN not set")
      end
    end
  end
end
