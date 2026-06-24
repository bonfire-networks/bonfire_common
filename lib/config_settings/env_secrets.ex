defmodule Bonfire.Common.EnvSecrets do
  @moduledoc """
  Dependency-free helper to provide secrets via files instead of exposing them in the environment.

  Implements the standard secrets-file convention (Docker secrets, systemd `LoadCredential=`, Kubernetes mounted secrets): for any `<NAME>_FILE` environment variable, the secret `<NAME>` is read from the file at that path. This keeps sensitive values out of the process environment, where they otherwise leak across the process tree and to other clients. See bonfire-app#1663.

  This module deliberately has **no dependencies** (only the Elixir/Erlang stdlib) so it can be called in any config file.
  """

  @doc """
  Reads the secret `name` from the environment, falling back to a file or a default value.

  Returns `System.get_env(name)` if it is set and non-empty; otherwise, if `<name>_FILE` is set, the trimmed contents of the file at that path; otherwise `default`.

  An explicitly-set (non-empty) env var always takes precedence over its `<name>_FILE`. An empty env var is treated as unset (so it falls through to the file). Missing/unreadable files are skipped (with a warning) and yield `default`.

  ## Examples

      iex> System.put_env("BONFIRE_TEST_SECRET", "from-env")
      iex> Bonfire.Common.EnvSecrets.env_or_file("BONFIRE_TEST_SECRET")
      "from-env"

      iex> System.delete_env("BONFIRE_TEST_SECRET")
      iex> Bonfire.Common.EnvSecrets.env_or_file("BONFIRE_TEST_SECRET", "fallback")
      "fallback"
  """
  def env_or_file(name, default \\ nil) when is_binary(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case System.get_env(name <> "_FILE") do
          path when is_binary(path) and path != "" -> read_file(path) || default
          _ -> default
        end
    end
  end

  @doc """
  Like `env_or_file/2` but raises if the secret is provided via neither the env var nor a readable `<name>_FILE`. Use in place of `System.fetch_env!/1`.
  """
  def env_or_file!(name) when is_binary(name) do
    env_or_file(name) ||
      raise "Missing secret: set the env var #{name}, or point #{name}_FILE at a readable file"
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        String.trim(contents)

      {:error, reason} ->
        IO.warn("Could not read secret file at #{path}: #{inspect(reason)}")
        nil
    end
  end
end
