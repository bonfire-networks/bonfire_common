defmodule Mix.Tasks.Bonfire.Secrets do
  @shortdoc "Generates some secrets"

  @moduledoc """
  Generates secrets and prints to the terminal.
      mix bonfire.secrets [length]
  By default, it generates keys 64 characters long.
  The minimum value for `length` is 32.
  """
  use Mix.Task

  # for running as escript
  def main(args) do
    # IO.inspect(args)
    run(args)
  end

  @doc false
  def run([]), do: run(["64"])

  def run(["--file", path]), do: update_env_secrets(path)

  def run([int]),
    do: int |> parse!() |> random_string() |> print()

  def run([int, iterate]), do: for(_ <- 1..parse!(iterate), do: run([int]))
  def run(args), do: invalid_args!(args)

  defp parse!(int) do
    case Integer.parse(int) do
      {int, ""} -> int
      _ -> invalid_args!(int)
    end
  end

  def print(int),
    do: "\r\n#{int}" |> IO.puts()

  defp random_string(length) when length > 31 do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end

  defp random_string(_),
    do: raise("Secrets should be at least 32 characters long")

  defp invalid_args!(args) do
    raise "Expected a length as integer or no argument at all, got #{inspect(args)}"
  end

  @secret_regexes [
    ~r/^(SECRET_KEY_BASE=)(.*)$/m,
    ~r/^(SIGNING_SALT=)(.*)$/m,
    ~r/^(ENCRYPTION_SALT=)(.*)$/m
  ]

  @pw_regexes [
    {"Postgres DB password", ~r/^(POSTGRES_PASSWORD=)(.*)$/m},
    {"MeiliSearch password", ~r/^(MEILI_MASTER_KEY=)(.*)$/m}
  ]

  defp update_env_secrets(file_path) do
    with {:ok, content} <- File.read(file_path) do
      new_content =
        Enum.reduce(@secret_regexes, content, fn regex, acc ->
          secret = random_string(64)
          print(secret)
          String.replace(acc, regex, "\\1#{secret}")
        end)

      content =
        if confirm_update(
             "the Phoenix secret keybase, signing salt, and encryption salt with the above in #{file_path}"
           ) do
          new_content
        else
          content
        end

      content =
        Enum.reduce(@pw_regexes, content, fn {detail, regex}, acc ->
          secret = random_string(32)
          print(secret)

          if confirm_update(
               "the #{detail} with the above in #{file_path} (NOTE: if using docker and you've already started the container before, this will not update the server's password and cause the connection to fail)"
             ) do
            String.replace(acc, regex, "\\1#{secret}")
          else
            acc
          end
        end)

      File.write(file_path, content)
    else
      e -> IO.inspect(e)
    end
  end

  defp confirm_update(details) do
    IO.puts("\r\nDo you want to replace #{details}? (y/n)")

    case IO.gets("") |> String.trim() |> String.downcase() do
      "y" -> true
      _ -> false
    end
  end
end
