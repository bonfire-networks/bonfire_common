defmodule Bonfire.Common.TriggerCITest do
  use ExUnit.Case, async: true

  alias Bonfire.Common.TriggerCI

  setup do
    # Configure Req.Test for this specific test module  
    Process.put([:bonfire_posts, :req_options], plug: {Req.Test, :trigger_ci_test})
    Req.Test.set_req_test_to_private()
    :ok
  end

  describe "trigger_rebuild/6" do
    test "handles GitHub with default host" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/dispatches"

        assert List.keyfind(conn.req_headers, "authorization", 0) ==
                 {"authorization", "token github_token"}

        # Parse JSON body properly
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        parsed_body = Jason.decode!(body)
        assert parsed_body["event_type"] == "push"
        assert parsed_body["client_payload"]["branch"] == "main"
        assert parsed_body["client_payload"]["reason"] == "test trigger"

        Req.Test.json(conn, %{})
      end)

      result =
        TriggerCI.trigger_rebuild(:github, "owner", "repo", "github_token",
          reason: "test trigger"
        )

      assert {:ok, %{provider: :github, method: :repository_dispatch, status: :success}} = result
    end

    test "handles GitHub with explicit host" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v3/repos/owner/repo/dispatches"

        Req.Test.json(conn, %{})
      end)

      result =
        TriggerCI.trigger_rebuild(
          :github,
          "github.enterprise.com",
          "owner",
          "repo",
          "github_token"
        )

      assert {:ok, %{provider: :github, method: :repository_dispatch, status: :success}} = result
    end

    test "handles GitHub workflow dispatch" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/owner/repo/actions/workflows/deploy.yml/dispatches"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        parsed_body = Jason.decode!(body)
        assert parsed_body["ref"] == "develop"
        assert parsed_body["inputs"]["reason"] == "manual trigger"
        assert parsed_body["inputs"]["custom_var"] == "value"

        Req.Test.json(conn, %{})
      end)

      result =
        TriggerCI.trigger_rebuild(:github, "owner", "repo", "github_token",
          workflow_id: "deploy.yml",
          branch: "develop",
          reason: "manual trigger",
          variables: %{custom_var: "value"}
        )

      assert {:ok, %{provider: :github, method: :workflow_dispatch, status: :success}} = result
    end

    test "handles GitLab pipeline trigger" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path =~ "/projects/owner%2Frepo/trigger/pipeline"

        # Parse form body properly for GitLab
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        form_data = URI.decode_query(body)
        assert form_data["token"] == "gitlab_token"
        assert form_data["ref"] == "main"
        assert form_data["variables[env]"] == "production"

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{id: 12345, status: "pending"})
      end)

      result =
        TriggerCI.trigger_rebuild(:gitlab, "owner", "repo", "gitlab_token",
          variables: %{env: "production"}
        )

      assert {:ok,
              %{
                provider: :gitlab,
                method: :pipeline_trigger,
                status: :success,
                response: %{"id" => 12345}
              }} = result
    end

    test "handles GitLab self-hosted instance" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path =~ "/projects/owner%2Frepo/trigger/pipeline"

        # Parse form body properly for GitLab
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        form_data = URI.decode_query(body)
        assert form_data["token"] == "gitlab_token"
        assert form_data["ref"] == "main"

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{id: 54321})
      end)

      result =
        TriggerCI.trigger_rebuild(:gitlab, "gitlab.company.com", "owner", "repo", "gitlab_token")

      assert {:ok, %{provider: :gitlab, method: :pipeline_trigger, status: :success}} = result
    end

    test "handles Drone CI trigger" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/repos/owner/repo/builds"

        assert List.keyfind(conn.req_headers, "authorization", 0) ==
                 {"authorization", "Bearer drone_token"}

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        parsed_body = Jason.decode!(body)
        assert parsed_body["branch"] == "staging"
        assert parsed_body["message"] == "deploy to staging"

        Req.Test.json(conn, %{number: 42, status: "pending"})
      end)

      result =
        TriggerCI.trigger_rebuild(:drone, "drone.company.com", "owner", "repo", "drone_token",
          branch: "staging",
          reason: "deploy to staging"
        )

      assert {:ok,
              %{
                provider: :drone,
                method: :build_trigger,
                status: :success,
                response: %{"number" => 42}
              }} = result
    end

    test "handles Gitea Actions" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/repos/owner/repo/dispatches"

        assert List.keyfind(conn.req_headers, "authorization", 0) ==
                 {"authorization", "token gitea_token"}

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        parsed_body = Jason.decode!(body)
        assert parsed_body["event_type"] == "push"
        assert parsed_body["client_payload"]["branch"] == "feature-branch"

        Req.Test.json(conn, %{})
      end)

      result =
        TriggerCI.trigger_rebuild(:gitea, "git.company.com", "owner", "repo", "gitea_token",
          branch: "feature-branch"
        )

      assert {:ok, %{provider: :gitea, method: :repository_dispatch, status: :success}} = result
    end

    test "handles unsupported provider" do
      result = TriggerCI.trigger_rebuild(:unsupported, "example.com", "owner", "repo", "token")

      assert {:error, "Unsupported provider: unsupported"} = result
    end

    test "handles HTTP errors gracefully" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{message: "Bad credentials"})
      end)

      result = TriggerCI.trigger_rebuild(:github, "owner", "repo", "bad_token")

      assert {:error, "Github API returned 401: " <> _} = result
    end

    test "handles network failures" do
      Req.Test.stub(:trigger_ci_test, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      result = TriggerCI.trigger_rebuild(:github, "owner", "repo", "timeout_token")

      assert {:error, "HTTP request failed: " <> _} = result
    end
  end
end
