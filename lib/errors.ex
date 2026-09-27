defmodule Bonfire.Common.Errors do
  @moduledoc "Helpers for handling error messages and exceptions"

  import Untangle
  require Logger
  import Bonfire.Common.Extend
  alias Bonfire.Common.Utils
  use Bonfire.Common.Config

  @doc """
  Turns various kinds of errors into an error message string. Used to format errors in a way that can be easily read by the user.

  ## Examples

      iex> error_msg([{:error, "something went wrong"}])
      ["something went wrong"]

      iex> error_msg(%{message: "custom error"})
      "custom error"

      iex> error_msg(:some_other_error)
      ":some_other_error"
  """
  def error_msg(errors) when is_list(errors) do
    errors
    |> Enum.map(&error_msg/1)

    # |> Enum.join("\n")
  end

  def error_msg(%Ecto.Changeset{} = cs),
    do: EctoSparkles.Changesets.Errors.changeset_errors_string(cs)

  def error_msg(exception) when is_exception(exception), do: Exception.message(exception)
  def error_msg(%{message: message}), do: error_msg(message)
  def error_msg({:error, :not_found}), do: "Not found"
  def error_msg({:error, error}), do: error_msg(error)

  def error_msg(%{__struct__: struct} = epic) when struct == Bonfire.Epics.Epic,
    do: Utils.maybe_apply(Bonfire.Epics.Epic, :render_errors, [epic])

  def error_msg(%{errors: errors}), do: error_msg(errors)
  def error_msg(%{error: error}), do: error_msg(error)
  def error_msg(%{term: term}), do: error_msg(term)
  def error_msg(message) when is_binary(message), do: message
  def error_msg(message), do: inspect(message)

  @spec maybe_ok_error(any, any) :: any
  @doc """
  Applies `change_fn` if the first parameter is an `{:ok, val}` tuple, else returns the value.

  ## Examples

      iex> maybe_ok_error({:ok, 42}, &(&1 * 2))
      {:ok, 84}

      iex> maybe_ok_error({:error, :some_error}, &(&1 * 2))
      {:error, :some_error}

      iex> maybe_ok_error(42, &(&1 * 2))
      42
  """
  def maybe_ok_error({:ok, val}, change_fn) do
    {:ok, change_fn.(val)}
  end

  def maybe_ok_error(other, _change_fn), do: other

  @doc """
  Maps an error tuple to a new value using the provided function.

  ## Examples

      iex> map_error({:error, :some_error}, &(&1 |> to_string()))
      "some_error"

      iex> map_error(42, &(&1 * 2))
      42
  """
  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  @doc """
  Replaces the error value in an error tuple with a new value.

  ## Examples

      iex> replace_error({:error, :old_value}, :new_value)
      {:error, :new_value}

      iex> replace_error(42, :new_value)
      42
  """
  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  @doc """
  Logs a debug message with exception and stacktrace information.

  ## Examples

      iex> debug_exception("An error occurred", %RuntimeError{message: "error"}, nil, :error, [])
      # Output: An error occurred: %RuntimeError{message: "error"}
      {:error, "An error occurred"}

  """
  def debug_exception(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error, opts \\ [])

  def debug_exception(msg, exception, stacktrace, kind, opts) do
    {error_msg, exception} =
      if is_exception(exception) do
        {error_msg(msg), exception}
      else
        if is_nil(exception) do
          {error_msg(msg), nil}
        else
          {[error_msg(msg), error_msg(exception)], nil}
        end
      end

    if Config.env() == :dev and
         Config.get(:show_debug_errors_in_dev) != false do
      {exception_banner, formatted_stacktrace} =
        debug_banner_with_trace(kind, exception, stacktrace, opts)

      debug_log_with_banner(msg, exception, exception_banner, stacktrace, error_msg)
      # error(stacktrace, inspect exception_banner)

      # Only surface the banner + stacktrace in the UI for actual exceptions.
      # Expected, control-flow errors (e.g. a thrown friendly message with no
      # real crash) just show the message — the full trace is still logged above.
      if is_nil(exception) do
        {:error, error_msg}
      else
        {:error,
         Enum.join(
           Bonfire.Common.Enums.filter_empty(
             [
               error_msg,
               "",
               to_string(exception_banner) |> String.slice(0..1000),
               "\n",
               to_string(formatted_stacktrace) |> String.slice(0..1000),
               ""
             ],
             []
           ),
           "\n"
         )
         |> String.slice(0..3000)}
      end
    else
      debug_log(msg, exception, stacktrace, kind, error_msg)
      {:error, error_msg}
    end
  end

  # TODO: as opts to format_stacktrace instead
  # defp maybe_stacktrace(stacktrace) when not is_nil(stacktrace) and stacktrace != "",
  #   do: "```\n#{stacktrace |> String.slice(0..2000)}\n```"

  # defp maybe_stacktrace(_), do: nil

  @doc """
  Logs a debug message with optional exception and stacktrace information.

  ## Examples

      > debug_log("A debug message", %RuntimeError{message: "error"}, nil, :error)
      # Output: A debug message: %RuntimeError{message: "error"}

      > debug_log("A debug message", nil, nil, :info)
      # Output: A debug message: nil
  """
  def debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error, msg_text \\ nil) do
    msg_text = msg_text || error_msg(msg)

    if exception && stacktrace do
      {exception_banner, formatted_stacktrace} =
        debug_banner_with_trace(kind, exception, stacktrace)

      # exception_banner = debug_banner(kind, exception, stacktrace)

      # slice the banner (may inline a huge inspected term) so the stacktrace after it survives Logger's `:truncate`
      reserved =
        String.length(to_string(msg_text)) + String.length(to_string(formatted_stacktrace)) + 8

      Logger.error(
        "#{msg_text} - #{sliced_banner(exception_banner, reserved)}\n#{formatted_stacktrace}",
        limit: :infinity,
        printable_limit: :infinity
      )

      # Logger.warning(stacktrace, truncate: :infinity)
    else
      Logger.error("#{msg_text} - #{inspect(exception)}")
    end

    debug_maybe_sentry(msg, exception, stacktrace)
  end

  defp debug_log_with_banner(
         msg,
         exception,
         exception_banner \\ nil,
         stacktrace \\ nil,
         msg_text \\ nil
       ) do
    msg_text = msg_text || error_msg(msg)
    formatted_stacktrace = format_stacktrace(stacktrace, [])

    reserved =
      String.length(to_string(msg_text)) + String.length(to_string(formatted_stacktrace)) + 8

    Logger.error(
      "#{msg_text} - #{sliced_banner(exception_banner || exception, reserved)}\n#{formatted_stacktrace}",
      limit: :infinity,
      printable_limit: :infinity
    )

    debug_maybe_sentry(msg, exception, stacktrace)
  end

  defp debug_maybe_sentry(msg, {:error, %_{} = exception}, stacktrace),
    do: debug_maybe_sentry(msg, exception, stacktrace)

  # FIXME: sentry lib often crashes
  defp debug_maybe_sentry(msg, exception, stacktrace)
       when not is_nil(stacktrace) and stacktrace != [] and
              is_exception(exception) do
    if Bonfire.Common.Errors.maybe_sentry_dsn() do
      Sentry.capture_exception(
        exception,
        stacktrace: stacktrace,
        extra: Bonfire.Common.Enums.map_new(msg, :error)
      )

      # |> debug()
    end
  end

  defp debug_maybe_sentry(msg, error, stacktrace) do
    if Bonfire.Common.Errors.maybe_sentry_dsn() do
      Sentry.capture_message(
        inspect(error,
          stacktrace: stacktrace || [],
          extra: Bonfire.Common.Enums.map_new(msg, :error)
        )
      )

      # |> debug()
    end
  end

  def maybe_sentry_dsn do
    case Bonfire.Common.Extend.extension_enabled?(:sentry) and Sentry.Config.dsn() do
      dsn when is_binary(dsn) ->
        dsn

      _ ->
        nil
    end
  end

  @ip_headers ~w(x-forwarded-for x-real-ip forwarded cf-connecting-ip true-client-ip x-client-ip)

  @doc """
  Sentry `before_send` callback that removes client IP addresses from every event, whichever integration captured it: `user.ip_address` (set by `Sentry.LiveViewHook`), `REMOTE_ADDR` (set by `Sentry.PlugContext`), and the proxy headers that carry the same address.
  """
  def sentry_before_send(%{request: request, user: user} = event) do
    %{
      event
      | user: if(is_map(user), do: Map.delete(user, :ip_address), else: user),
        request: sentry_strip_request_ip(request)
    }
  end

  def sentry_before_send(event), do: event

  defp sentry_strip_request_ip(%{env: env, headers: headers} = request) do
    %{
      request
      | env: if(is_map(env), do: Map.delete(env, "REMOTE_ADDR"), else: env),
        headers: if(is_map(headers), do: Map.drop(headers, @ip_headers), else: headers)
    }
  end

  defp sentry_strip_request_ip(request), do: request

  def debug_banner_with_trace(kind, exception, stacktrace, opts \\ []) do
    exception = if exception, do: debug_banner(kind, exception, stacktrace, opts)
    stacktrace = if stacktrace, do: format_stacktrace(stacktrace, stacktrace_opts(opts))
    {exception, stacktrace}
  end

  def debug_banner(kind, errors, stacktrace, opts \\ [])

  def debug_banner(kind, errors, stacktrace, opts) when is_list(errors) do
    errors
    |> Enum.map(&debug_banner(kind, &1, stacktrace, opts))
    |> Enum.join("\n")
  end

  def debug_banner(kind, {:error, error}, stacktrace, opts) do
    debug_banner(kind, error, stacktrace, opts)
  end

  # def debug_banner(_kind, %Ecto.Changeset{} = _cs, _, _opts) do
  #   # TODO?
  #   EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  # end

  def debug_banner(kind, %_{} = exception, stacktrace, opts)
      when not is_nil(stacktrace) and stacktrace != [] do
    format_banner(kind, exception, stacktrace, opts)
  end

  def debug_banner(_kind, exception, _stacktrace, _opts) when is_binary(exception) do
    exception
  end

  def debug_banner(_kind, exception, _stacktrace, _opts) do
    inspect(exception)
  end

  def mf_maybe_link_to_code(text \\ nil, mod, fun, opts) do
    mf = "#{mod}.#{fun}"

    if opts[:as_markdown] do
      "[#{text || mf}](/settings/extensions/code/#{mod}/#{fun})"
    else
      "#{text || mf}"
    end
  end

  def module_maybe_link_to_code(text \\ nil, mod, opts) do
    if opts[:as_markdown] do
      "[#{text || mod}](/settings/extensions/code/#{mod})"
    else
      "#{text || mod}"
    end
  end

  @doc """
  Normalizes and formats any throw/error/exit. The message is formatted and displayed in the same format as used by Elixir's CLI.

  The third argument is the stacktrace which is used to enrich a normalized error with more information. It is only used when the kind is an error.

  ## Examples

      iex> format_banner(:error, %RuntimeError{message: "error"})
      "** Elixir.RuntimeError: error"

      iex> format_banner(:throw, :some_reason)
      "** (throw) :some_reason"

      iex> format_banner(:exit, :some_reason)
      "** (exit) :some_reason"

      > format_banner({:EXIT, self()}, :some_reason)
      "** (EXIT from #PID<0.780.0>) :some_reason"
  """
  def format_banner(kind, exception, stacktrace \\ [], opts \\ [])

  def format_banner(:error, exception, stacktrace, opts) do
    exception = Exception.normalize(:error, exception, stacktrace)

    "** " <>
      module_maybe_link_to_code(exception.__struct__, opts) <>
      ": " <> Exception.message(exception)
  end

  def format_banner(:throw, reason, _stacktrace, _opts) do
    "** (throw) " <> inspect(reason)
  end

  def format_banner(:exit, reason, _stacktrace, _opts) do
    "** (exit) " <> Exception.format_exit(reason)
  end

  def format_banner({:EXIT, pid}, reason, _stacktrace, _opts) do
    "** (EXIT from #{inspect(pid)}) " <> Exception.format_exit(reason)
  end

  # An exception's banner (its type and message) is what says what went wrong, so it keeps up to half the log line's budget even when the stacktrace after it needs more. The line then exceeds the budget and Logger trims its tail, which is the deepest frames, the least useful end
  defp sliced_banner(banner, reserved) do
    slice_to_log_limit(banner,
      reserved: reserved,
      min:
        case log_truncate_limit() do
          limit when is_integer(limit) -> div(limit, 2)
          _ -> nil
        end
    )
  end

  # how `Untangle.format_stacktrace/2` lays a stacktrace out for where it is shown: in the in-app error view (`as_markdown`) each frame's location links to its code, frames are not indented (four spaces would make a markdown code block, where links don't render), and each is capped so one frame can't fill the view
  defp stacktrace_opts(opts) do
    if opts[:as_markdown],
      do: [
        indent: "",
        link_to_code: &mf_maybe_link_to_code(&1, &2, &3, opts),
        entry_max_length: 200
      ],
      else: []
  end
end
