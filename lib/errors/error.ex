defmodule Bonfire.Common.Error do
  require Logger
  alias __MODULE__
  alias Ecto.Changeset

  defstruct [:code, :message, :status]

  @common_errors Application.get_env(:bonfire_common, :common_errors) || []
  @error_list Map.keys(@common_errors)

  # Error Tuples
  # ------------

  # Regular errors
  def error({:error, reason}) do
    handle(reason)
  end

  def error({:error, reason, extra}) do
    handle(reason, extra)
  end

  # Ecto transaction errors
  def error({:error, _operation, reason, _changes}) do
    handle(reason)
  end

  # Unhandled errors
  def error(other) do
    handle(other)
  end

  def error(other, extra) do
    handle(other, extra)
  end

  # Handle Different Errors
  # -----------------------

  defp handle(reason, extra \\ "")

  defp handle(reason, %Ecto.Changeset{} = changeset),
    do: handle(reason, changeset_nessage(changeset))

  defp handle(code, extra) when is_atom(code) do
    {status, message} = metadata(code, extra)

    return(%Error{
      code: code,
      message: message,
      status: status
    })
  end

  defp handle(status, extra) when is_integer(status) do
    return(%Error{
      code: status,
      message: "#{extra}",
      status: status
    })
  end

  defp handle(message, extra) when is_binary(message) do
    status = 500

    return(%Error{
      code: status,
      message: "#{message} #{extra}",
      status: status
    })
  end

  defp handle(errors, _) when is_list(errors) do
    Enum.map(errors, &handle/1)
  end

  defp handle(%Ecto.Changeset{} = changeset, _) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {err, _opts} -> err end)
    |> Enum.map(fn {k, v} ->
      return(%Error{
        code: :validation,
        message: String.capitalize("#{k} #{v}"),
        status: 422
      })
    end)
  end

  def changeset_nessage(%Changeset{} = changeset) do
    {_key, {message, _args}} = changeset.errors |> List.first()
    message |> String.trim("\"")
  end

  defp return(error) do
    Logger.warn("#{inspect(error)}")
    error
  end

  # ... Handle other error types here ...

  defp handle(other, extra) do
    Logger.error("Unhandled error type:\n#{inspect(other)} #{inspect(extra)}")
    handle(:unknown, extra)
  end

  # Build Error Metadata
  # --------------------
  def metadata(error_term, error_applies_to \\ "")

  def metadata(error_term, extra) when error_term in @error_list do
    {status, message} = @common_errors[error_term]
    show = String.replace(message, "%s", extra)

    if show == message do
      {status, "#{show} #{extra}"}
    else
      {status, "#{show}"}
    end
  end

  def metadata(code, extra) do
    Logger.error("Unhandled error code: #{inspect(code)} #{inspect(extra)}")
    {422, "Error (#{code}) #{inspect(extra)}"}
  end
end
