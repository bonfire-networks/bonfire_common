defmodule Bonfire.Common.AntiSpam.Akismet do
  @moduledoc """
  Integration with Akismet.com for spam detection

  Credit to https://joinmobilizon.org for the original code.
  """
  use Bonfire.Common.Utils

  # TODO: migrate to a newer library? like https://github.com/PerpetualCreativity/akismet 
  alias Exkismet.Comment, as: AkismetComment
  alias Bonfire.Common.AntiSpam.Provider

  @behaviour Provider

  @impl Provider
  def check_current_user(context) do
    check_content(
      %{
        comment_type: "signup"
      },
      context
    )
  end

  @impl Provider
  def check_profile(text, context) do
    check_content(
      %{
        comment_content: text,
        comment_type: "signup"
      },
      context
    )
  end

  @impl Provider
  def check_object(text, context) do
    check_content(
      %{
        comment_content: text,
        comment_type: "blog-post"
      },
      context
    )
  end

  @impl Provider
  def check_comment(
        comment_body,
        is_reply?,
        context
      ) do
    check_content(
      %{
        comment_content: comment_body,
        comment_type: if(is_reply?, do: "reply", else: "comment")
      },
      context
    )
  end

  defp check_content(comment, context) do
    if Config.get(:env) != :test and ready?() do
      # debug(context)
      current_user = current_user(context)
      current_account = current_account(context)

      Map.merge(
        %AkismetComment{
          blog: homepage(),
          user_ip: maybe_from_opts(context, :user_ip),
          comment_author: e(current_user, :character, :username, nil),
          #  to always mark as spam
          comment_author_email: "akismet-guaranteed-spam@example.com",
          # comment_author_email: e(current_account, :email, :email_address, nil) || maybe_apply(Bonfire.Me.Characters, :display_username, [current_user, true, nil, ""], fallback_return: nil),
          user_agent: maybe_from_opts(context, :user_agent),
          permalink: URIs.canonical_url(maybe_from_opts(context, :current_url)),
          is_test: Config.env() != :prod
        },
        comment
      )
      |> debug("AkismetComment")
      |> Exkismet.comment_check(key: api_key())
      |> debug("spam_result")
    else
      :ham
    end
  end

  def report_ham(user, text) do
    report_to_akismet_comment(user, text)
    |> submit_ham()
  end

  def report_spam(user, text) do
    report_to_akismet_comment(user, text)
    |> submit_spam()
  end

  @spec homepage() :: String.t()
  defp homepage do
    Bonfire.Common.URIs.base_url()
  end

  defp api_key do
    Config.get([__MODULE__, :api_key])
  end

  @impl Provider
  def ready?, do: not is_nil(api_key())

  defp report_to_akismet_comment(user, object \\ nil)

  defp report_to_akismet_comment(user, nil) do
    case actor_details(user) do
      {email, preferred_username, ip} ->
        %AkismetComment{
          blog: homepage(),
          comment_author_email: email,
          comment_author: preferred_username,
          user_ip: ip
        }

      {:error, err} ->
        {:error, err}

      err ->
        {:error, err}
    end
  end

  defp report_to_akismet_comment(user, text) do
    with {email, preferred_username, ip} <- actor_details(user) do
      %AkismetComment{
        comment_content: text,
        blog: homepage(),
        comment_author_email: email,
        comment_author: preferred_username,
        user_ip: ip
      }
    else
      {:error, err} ->
        {:error, err}

      err ->
        {:error, err}
    end
  end

  @spec actor_details(Actor.t()) :: {String.t(), String.t(), any()} | {:error, :invalid_actor}
  defp actor_details(%{
         type: :Person,
         preferred_username: preferred_username,
         user: %{
           current_sign_in_ip: current_sign_in_ip,
           last_sign_in_ip: last_sign_in_ip,
           email: email
         }
       }) do
    {email, preferred_username, current_sign_in_ip || last_sign_in_ip}
  end

  defp actor_details(%{
         type: :Person,
         preferred_username: preferred_username,
         user_id: user_id
       })
       when not is_nil(user_id) do
    case user_id |> Users.get_user() |> user_details() do
      {email, ip} ->
        {preferred_username, email, ip}

      _ ->
        {:error, :invalid_actor}
    end
  end

  defp actor_details(%{
         type: :Person,
         preferred_username: preferred_username,
         user_id: nil
       }) do
    {nil, preferred_username, "127.0.0.1"}
  end

  defp actor_details(_) do
    {:error, :invalid_actor}
  end

  @spec user_details(User.t()) :: {String.t(), any()} | {:error, :user_not_found}
  defp user_details(%{
         current_sign_in_ip: current_sign_in_ip,
         last_sign_in_ip: last_sign_in_ip,
         email: email
       }) do
    {email, current_sign_in_ip || last_sign_in_ip}
  end

  defp user_details(_), do: {:error, :user_not_found}

  @spec submit_spam(AkismetComment.t() | :error) ::
          :ok | {:error, atom()} | {:error, HTTPoison.Response.t()}
  defp submit_spam(%AkismetComment{} = comment) do
    comment
    |> tap(fn comment ->
      info(comment, "Submitting content to Akismet as spam")
    end)
    |> Exkismet.submit_spam(key: api_key())
    |> log_response()
  end

  defp submit_spam({:error, err}), do: {:error, err}

  @spec submit_ham(AkismetComment.t() | :error) ::
          :ok | {:error, atom()} | {:error, HTTPoison.Response.t()}
  defp submit_ham(%AkismetComment{} = comment) do
    comment
    |> tap(fn comment ->
      info(comment, "Submitting content to Akismet as ham")
    end)
    |> Exkismet.submit_ham(key: api_key())
    |> log_response()
  end

  defp submit_ham({:error, err}), do: {:error, err}

  defp log_response(res),
    do: tap(res, fn res -> debug(res, "Return from Akismet is") end)
end
