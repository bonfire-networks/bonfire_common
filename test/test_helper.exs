# Test helper functions
defmodule Bonfire.Common.TestHelpers do
  @moduledoc """
  Helper functions for TriggerCI tests
  """

  def valid_github_payload do
    %{
      event_type: "push",
      client_payload: %{
        branch: "main",
        reason: "test trigger",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        triggered_by: "elixir_app",
        ref: "refs/heads/main",
        repository: %{
          name: "test-repo",
          full_name: "test-owner/test-repo",
          default_branch: "main"
        },
        pusher: %{
          name: "ci-trigger",
          email: "ci-trigger@github.com"
        }
      }
    }
  end

  def valid_gitlab_form_data do
    %{
      "variables[REBUILD_REASON]" => "test trigger",
      "variables[TRIGGERED_BY]" => "elixir_app",
      "variables[TRIGGER_TIMESTAMP]" => DateTime.utc_now() |> DateTime.to_iso8601(),
      token: "test-token",
      ref: "main"
    }
  end

  def mock_successful_response(provider) do
    case provider do
      :github -> {:ok, %{status: 204}}
      :gitlab -> {:ok, %{status: 201, body: %{"id" => 12345, "status" => "pending"}}}
      :drone -> {:ok, %{status: 200, body: %{"number" => 42, "status" => "pending"}}}
      :gitea -> {:ok, %{status: 204}}
    end
  end

  def mock_error_response(status \\ 401) do
    {:ok, %{status: status, body: %{"message" => "Unauthorized"}}}
  end

  def mock_network_error do
    {:error, %{reason: :timeout}}
  end
end

# Only run integration tests when explicitly requested
if System.get_env("RUN_INTEGRATION_TESTS") == "true" do
  ExUnit.start(exclude: Bonfire.Common.RuntimeConfig.skip_test_tags())
else
  ExUnit.configure(exclude: [:integration], formatters: [ExUnit.CLIFormatter])
  # Configure the application to use Req.Test in test environment with a simple atom name
  Application.put_env(:bonfire_posts, :req_options, plug: {Req.Test, :trigger_ci_test})
  ExUnit.start(exclude: Bonfire.Common.RuntimeConfig.skip_test_tags() ++ [:integration])
end

# Ecto.Adapters.SQL.Sandbox.mode(
#   Bonfire.Common.Config.repo(),
#   :manual
# )
