defmodule Bonfire.Common.EnvSecretsTest do
  @moduledoc """
  Regression for bonfire-app#1663: secrets must be loadable from files (Docker secrets / systemd
  `LoadCredential`) via the standard `<NAME>_FILE` convention, instead of being exposed in the
  process environment.
  """
  use Bonfire.Common.DataCase, async: true
  alias Bonfire.Common.EnvSecrets

  # use a unique env var per test so async tests don't clobber each other
  defp unique_var, do: "BONFIRE_TEST_SECRET_#{System.unique_integer([:positive])}"

  defp tmp_secret(contents) do
    path = Path.join(System.tmp_dir!(), "bonfire_secret_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "returns the env var when set" do
    var = unique_var()
    System.put_env(var, "from-env")
    on_exit(fn -> System.delete_env(var) end)
    assert "from-env" == EnvSecrets.env_or_file(var)
  end

  test "reads NAME from NAME_FILE (trimmed) when NAME is unset" do
    var = unique_var()
    path = tmp_secret("  s3kr3t-value\n")
    System.put_env(var <> "_FILE", path)
    on_exit(fn -> System.delete_env(var <> "_FILE") end)
    assert "s3kr3t-value" == EnvSecrets.env_or_file(var)
  end

  test "an explicitly-set env var takes precedence over its *_FILE" do
    var = unique_var()
    path = tmp_secret("from-file")
    System.put_env(var, "from-env")
    System.put_env(var <> "_FILE", path)

    on_exit(fn ->
      System.delete_env(var)
      System.delete_env(var <> "_FILE")
    end)

    assert "from-env" == EnvSecrets.env_or_file(var)
  end

  test "treats an empty env var as unset and falls back to the file" do
    var = unique_var()
    path = tmp_secret("from-file")
    System.put_env(var, "")
    System.put_env(var <> "_FILE", path)

    on_exit(fn ->
      System.delete_env(var)
      System.delete_env(var <> "_FILE")
    end)

    assert "from-file" == EnvSecrets.env_or_file(var)
  end

  test "returns the default when neither env nor file is set" do
    assert "fallback" == EnvSecrets.env_or_file(unique_var(), "fallback")
    assert nil == EnvSecrets.env_or_file(unique_var())
  end

  test "returns the default when the *_FILE path is missing/unreadable" do
    var = unique_var()
    System.put_env(var <> "_FILE", "/nonexistent/path/xyz123")
    on_exit(fn -> System.delete_env(var <> "_FILE") end)
    assert "default" == EnvSecrets.env_or_file(var, "default")
  end

  test "env_or_file!/1 raises when neither env nor file is set" do
    assert_raise RuntimeError, ~r/Missing secret/, fn ->
      EnvSecrets.env_or_file!(unique_var())
    end
  end

  test "env_or_file!/1 returns the value from a file" do
    var = unique_var()
    path = tmp_secret("required-secret")
    System.put_env(var <> "_FILE", path)
    on_exit(fn -> System.delete_env(var <> "_FILE") end)
    assert "required-secret" == EnvSecrets.env_or_file!(var)
  end
end
