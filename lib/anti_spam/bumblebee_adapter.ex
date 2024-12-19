defmodule Bonfire.Common.AntiSpam.BumblebeeAdapter do
  @moduledoc """
  Integration with Bumblebee model(s) for anti-spam detection.
  """
  use Bonfire.Common.Utils

  alias Bonfire.Common.AntiSpam.Provider

  @behaviour Provider

  @impl Provider
  def check_current_user(_context) do
    # TODO: check profile instead?
    :ham
  end

  @impl Provider
  def check_profile(text, context) do
    check_content(
      %{
        comment_content: text
      },
      context
    )
  end

  @impl Provider
  def check_object(text, context) do
    check_content(
      %{
        #  contains name & bio
        comment_content: text
      },
      context
    )
  end

  @impl Provider
  def check_comment(
        comment_body,
        _is_reply?,
        context
      ) do
    check_content(
      %{
        comment_content: comment_body
      },
      context
    )
  end

  defp check_content(comment, context) do
    if Config.get(:env) != :test and ready?() do
      # debug(context)
      current_user = current_user(context)
      serving = prepare_serving()

      with %{
             predictions: predictions
           } =
             """
             #{e(current_user, :profile, :username, nil)} (#{maybe_apply(Bonfire.Me.Characters, :display_username, [current_user, true, nil, ""], fallback_return: nil)}): #{comment[:comment_content]}
             """
             |> debug("text to check")
             |> Nx.Serving.run(serving, ...),
           # |> debug("spam_result"),
           %{"LABEL_0" => [ham_score], "LABEL_1" => [spam_score]} <-
             Enum.group_by(predictions, &Map.get(&1, :label), &Map.get(&1, :score))
             |> debug("result") do
        cond do
          spam_score > 0.90 and ham_score < 0.5 -> :spam
          spam_score > 0.99 -> :spam
          true -> :ham
        end
      else
        other ->
          error(other, "Could not recognise response from AI model")
          :ham
      end
    else
      :ham
    end
  end

  defp prepare_serving(
         model \\ "mrm8488/bert-tiny-finetuned-enron-spam-detection",
         tokenizer \\ nil
       ) do
    {:ok, model_info} =
      Bumblebee.load_model({:hf, model})

    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, tokenizer || model})

    Bumblebee.Text.text_classification(model_info, tokenizer,
      compile: [batch_size: 1, sequence_length: 100],
      defn_options: [compiler: EXLA]
    )
  end

  @impl Provider
  def ready?, do: module_enabled?(Bumblebee)

  # defp log_response(res),
  #   do: tap(res, fn res -> debug(res, "Analysis from AI anti-spam is") end)
end
