# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Mailer.Checker do
  @moduledoc """
  Functions for checking the validity of email addresses and domains
  """
  alias EmailChecker.Check.{Format, MX}

  @type error_reason :: :format | :mx

  @spec validate_email(email :: binary) :: :ok | {:error, error_reason}
  @doc "Checks whether an email is valid, returns a reason if not"
  def validate_email(email) do
    config = config()
    check_format = Keyword.get(config, :format, true)
    check_mx = Keyword.get(config, :mx, true)

    cond do
      check_format and not Format.valid?(email) -> {:error, :format}
      check_mx and not MX.valid?(email) -> {:error, :mx}
      true -> :ok
    end
  end

  @domain_regex ~r/(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)/

  @spec validate_domain(domain :: binary) :: :ok | {:error, error_reason}
  @doc "Checks whether an email domain is valid, returns a reason if not"
  def validate_domain(domain) do
    if Regex.match?(@domain_regex, domain) do
      validate_email("test@" <> domain)
    else
      {:error, :format}
    end
  end

  defp config(), do: CommonsPub.Config.get(__MODULE__, [])
end
