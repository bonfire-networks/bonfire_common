defmodule Bonfire.Common.AntiSpam.Provider do
  @moduledoc """
  Provider Behaviour for anti-spam detection.

  ## Supported backends

    * `Bonfire.Common.AntiSpam.Akismet` [🔗](https://akismet.com/)

  """

  @type spam_result :: :ham | :spam | :discard
  @type result :: spam_result() | {:error, any()}

  @doc """
  Make sure the provider is ready
  """
  @callback ready?() :: boolean()

  @doc """
  Check an user details
  """
  @callback check_current_user(context :: any()) ::
              result()

  @doc """
  Check a profile details
  """
  @callback check_profile(
              summary :: String.t(),
              context :: any()
            ) :: result()

  @doc """
  Check an object details (such as a blog post)
  """
  @callback check_object(
              body :: String.t(),
              context :: any()
            ) :: result()

  @doc """
  Check a comment (or microblog) details
  """
  @callback check_comment(
              comment_body :: String.t(),
              is_reply? :: boolean(),
              context :: any()
            ) :: result()

  @callback report_ham(user :: any(), text :: String.t() | nil) ::
              :ok | {:error, atom()} | {:error, HTTPoison.Response.t()}

  @callback report_spam(user :: any(), text :: String.t() | nil) ::
              :ok | {:error, atom()} | {:error, HTTPoison.Response.t()}
end
