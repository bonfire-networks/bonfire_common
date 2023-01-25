defmodule Bonfire.Common.Errors do
  import Untangle
  require Logger
  import Bonfire.Common.Extend
  alias Bonfire.Common.Config

  @spec maybe_ok_error(any, any) :: any
  @doc "Applies change_fn if the first parameter is an {:ok, val} tuple, else returns the value"
  def maybe_ok_error({:ok, val}, change_fn) do
    {:ok, change_fn.(val)}
  end

  def maybe_ok_error(other, _change_fn), do: other

  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  def debug_exception(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_exception(%Ecto.Changeset{} = cs, exception, stacktrace, kind) do
    debug_exception(
      EctoSparkles.Changesets.Errors.changeset_errors_string(cs),
      exception,
      stacktrace,
      kind
    )
  end

  def debug_exception(msg, exception, stacktrace, kind) do
    debug_log(msg, exception, stacktrace, kind)

    if Config.get!(:env) == :dev and
         Config.get(:show_debug_errors_in_dev) != false do
      {exception, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      {:error,
       Enum.join(
         Bonfire.Common.Enums.filter_empty(
           [error_msg(msg), exception, maybe_stacktrace(stacktrace)],
           []
         ),
         "\n"
       )
       |> String.slice(0..3000)}
    else
      {:error, error_msg(msg)}
    end
  end

  defp maybe_stacktrace(stacktrace) when not is_nil(stacktrace) and stacktrace != "",
    do: "```\n#{stacktrace |> String.slice(0..2000)}\n```"

  defp maybe_stacktrace(_), do: nil

  def debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_log(msg, exception, stacktrace, kind) do
    error(exception, msg)

    if exception && stacktrace do
      {exception, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      Logger.info(stacktrace, limit: :infinity, printable_limit: :infinity)
      # Logger.warn(stacktrace, truncate: :infinity)
    end

    debug_maybe_sentry(msg, exception, stacktrace)
  end

  defp debug_maybe_sentry(msg, {:error, %_{} = exception}, stacktrace),
    do: debug_maybe_sentry(msg, exception, stacktrace)

  # FIXME: sentry lib often crashes
  defp debug_maybe_sentry(msg, exception, stacktrace)
       when not is_nil(stacktrace) and stacktrace != [] and
              is_exception(exception) do
    if module_enabled?(Sentry) do
      Sentry.capture_exception(
        exception,
        stacktrace: stacktrace,
        extra: Bonfire.Common.Enums.map_new(msg, :error)
      )
      |> debug()
    end
  end

  defp debug_maybe_sentry(msg, error, stacktrace) do
    if module_enabled?(Sentry) do
      Sentry.capture_message(
        inspect(error,
          stacktrace: stacktrace,
          extra: Bonfire.Common.Enums.map_new(msg, :error)
        )
      )
      |> debug()
    end
  end

  defp debug_maybe_sentry(_, _, _stacktrace), do: nil

  def debug_banner_with_trace(kind, exception, stacktrace) do
    exception = if exception, do: debug_banner(kind, exception, stacktrace)
    stacktrace = if stacktrace, do: Exception.format_stacktrace(stacktrace)
    {exception, stacktrace}
  end

  defp debug_banner(kind, errors, stacktrace) when is_list(errors) do
    errors
    |> Enum.map(&debug_banner(kind, &1, stacktrace))
    |> Enum.join("\n")
  end

  defp debug_banner(kind, {:error, error}, stacktrace) do
    debug_banner(kind, error, stacktrace)
  end

  defp debug_banner(_kind, %Ecto.Changeset{} = cs, _) do
    # EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  end

  defp debug_banner(kind, %_{} = exception, stacktrace)
       when not is_nil(stacktrace) and stacktrace != [] do
    inspect(Exception.format_banner(kind, exception, stacktrace))
  end

  defp debug_banner(_kind, exception, _stacktrace) when is_binary(exception) do
    exception
  end

  defp debug_banner(_kind, exception, _stacktrace) do
    inspect(exception)
  end

  def error_msg(errors) when is_list(errors) do
    errors
    |> Enum.map(&error_msg/1)
    |> Enum.join("\n")
  end

  def error_msg(%Ecto.Changeset{} = cs),
    do: EctoSparkles.Changesets.Errors.changeset_errors_string(cs)

  def error_msg(%{message: message}), do: error_msg(message)
  def error_msg({:error, :not_found}), do: "Not found"
  def error_msg({:error, error}), do: error_msg(error)

  def error_msg(%{__struct__: struct} = epic) when struct == Bonfire.Epics.Epic,
    do: Bonfire.Epics.Epic.render_errors(epic)

  def error_msg(%{errors: errors}), do: error_msg(errors)
  def error_msg(%{error: error}), do: error_msg(error)
  def error_msg(%{term: term}), do: error_msg(term)
  def error_msg(message) when is_binary(message), do: message
  def error_msg(message), do: inspect(message)
end
