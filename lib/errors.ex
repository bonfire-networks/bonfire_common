defmodule Bonfire.Common.Errors do
  @moduledoc "Helpers for handling error messages and exceptions"

  import Untangle, except: [format_stacktrace_entry: 1, format_location: 2, format_location: 1]
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

    debug_log(msg, exception, stacktrace, kind, error_msg)

    if Config.env() == :dev and
         Config.get(:show_debug_errors_in_dev) != false do
      {exception_banner, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace, opts)

      # error(stacktrace, inspect exception_banner)

      {:error,
       Enum.join(
         Bonfire.Common.Enums.filter_empty(
           [
             error_msg,
             "",
             to_string(exception_banner) |> String.slice(0..1000),
             "\n",
             to_string(stacktrace) |> String.slice(0..1000),
             ""
           ],
           []
         ),
         "\n"
       )
       |> String.slice(0..3000)}
    else
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
  def debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error, msg_text \\ nil)

  def debug_log(msg, exception, stacktrace, kind, msg_text) do
    msg_text = msg_text || error_msg(msg)

    if exception && stacktrace do
      {exception_banner, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      error(exception_banner, msg_text)
      Logger.info(stacktrace, limit: :infinity, printable_limit: :infinity)
      # Logger.warning(stacktrace, truncate: :infinity)
    else
      error(exception, msg_text)
    end

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

  def debug_banner_with_trace(kind, exception, stacktrace, opts \\ []) do
    exception = if exception, do: debug_banner(kind, exception, stacktrace, opts)
    stacktrace = if stacktrace, do: format_stacktrace(stacktrace, opts)
    {exception, stacktrace}
  end

  defp debug_banner(kind, errors, stacktrace, opts)

  defp debug_banner(kind, errors, stacktrace, opts) when is_list(errors) do
    errors
    |> Enum.map(&debug_banner(kind, &1, stacktrace, opts))
    |> Enum.join("\n")
  end

  defp debug_banner(kind, {:error, error}, stacktrace, opts) do
    debug_banner(kind, error, stacktrace, opts)
  end

  # defp debug_banner(_kind, %Ecto.Changeset{} = _cs, _, _opts) do
  #   # TODO?
  #   EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  # end

  defp debug_banner(kind, %_{} = exception, stacktrace, opts)
       when not is_nil(stacktrace) and stacktrace != [] do
    format_banner(kind, exception, stacktrace, opts)
  end

  defp debug_banner(_kind, exception, _stacktrace, _opts) when is_binary(exception) do
    exception
  end

  defp debug_banner(_kind, exception, _stacktrace, _opts) do
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

  @doc """
  Formats the stacktrace. A stacktrace must be given as an argument. If not, the stacktrace is retrieved from `Process.info/2`.

  # TODO: consolidate/reuse with similar function in `Untangle`?

  ## Examples

      > format_stacktrace([{MyModule, :my_fun, 1, [file: 'my_file.ex', line: 42]}], [])
      "my_file.ex:42: MyModule.my_fun/1"

      > format_stacktrace(nil, [])
      "stacktrace here..."
  """
  def format_stacktrace(trace \\ nil, opts \\ []) do
    case trace || last_stacktrace() do
      [] ->
        "\n"

      trace ->
        if opts[:as_markdown] do
          Enum.map_join(trace, "\n", &format_stacktrace_entry_sliced(&1, opts)) <> "\n"
        else
          Untangle.format_stacktrace(trace) <> "\n"
        end
    end
  end

  def last_stacktrace() do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, t} -> Enum.drop(t, 3)
    end
  end

  def format_stacktrace_entry_sliced(entry, opts),
    do:
      format_stacktrace_entry(
        entry,
        # |> IO.inspect(label: "eeee"),
        opts
      )
      |> String.slice(0..200)

  @doc """
  Receives a stacktrace entry and formats it into a string.

  ## Examples

      iex> format_stacktrace_entry({MyModule, :my_fun, 1, [file: 'my_file.ex', line: 42]}, [])
      "my_file.ex:42: MyModule.my_fun/1"

      > format_stacktrace_entry({fn -> :ok end, 0, [file: 'another_file.ex', line: 7]}, [])
      "another_file.ex:7: some_fun/2"
  """
  def format_stacktrace_entry(entry, opts \\ [])

  # From Macro.Env.stacktrace
  def format_stacktrace_entry({module, :__MODULE__, 0, location}, opts) do
    format_location(location) <> module_maybe_link_to_code(module, opts) <> " (module)"
  end

  # From :elixir_compiler_*
  def format_stacktrace_entry({_module, :__MODULE__, 1, location}, _opts) do
    format_location(location) <> "(module)"
  end

  # From :elixir_compiler_*
  def format_stacktrace_entry({_module, :__FILE__, 1, location}, _opts) do
    format_location(location) <> "(file)"
  end

  def format_stacktrace_entry({module, fun, arity, location}, opts) do
    with {mod, fun, mfa_formated} <- format_mfa(module, fun, arity) do
      format_application(module) <>
        mf_maybe_link_to_code(format_location(location), mod, fun, opts) <> mfa_formated
    else
      _ ->
        format_application(module) <>
          mf_maybe_link_to_code(format_location(location), module, fun, opts)
    end
  end

  def format_stacktrace_entry({fun, arity, location}, _opts) do
    format_location(location) <> Exception.format_fa(fun, arity)
  end

  @doc """
  Receives a module, function, and arity and formats it as shown in stacktraces. The arity may also be a list of arguments.

  Anonymous functions are reported as -func/arity-anonfn-count-, where func is the name of the enclosing function. Convert to "anonymous fn in func/arity"

  ## Examples

      iex> format_mfa(Foo, :bar, 1)
      {"Foo", "bar", "Foo.bar/1"}

      iex> format_mfa(Foo, :bar, [])
      {"Foo", "bar", "Foo.bar()"}

      iex> Exception.format_mfa(nil, :bar, [])
      "nil.bar()"
  """
  def format_mfa(module, fun, arity) when is_atom(module) and is_atom(fun) do
    if function_exported?(Macro, :inspect_atom, 2) do
      mod = Macro.inspect_atom(:literal, module)

      case Code.Identifier.extract_anonymous_fun_parent(fun) do
        {outer_name, outer_arity} ->
          fun = Macro.inspect_atom(:remote_call, outer_name)

          {mod, fun,
           "anonymous fn#{format_arity(arity)} in " <>
             "#{mod}." <>
             "#{fun}/#{outer_arity}"}

        :error ->
          fun = Macro.inspect_atom(:remote_call, fun)

          {mod, fun,
           "#{mod}." <>
             "#{fun}#{format_arity(arity)}"}
      end
    end
  end

  defp format_arity(arity) when is_list(arity) do
    inspected = for x <- arity, do: inspect(x)
    "(#{Enum.join(inspected, ", ")})"
  end

  defp format_arity(arity) when is_integer(arity) do
    "/" <> Integer.to_string(arity)
  end

  defp format_application(module) do
    # We cannot use Application due to bootstrap issues
    case :application.get_application(module) do
      {:ok, app} ->
        case :application.get_key(app, :vsn) do
          {:ok, vsn} when is_list(vsn) ->
            "" <> Atom.to_string(app) <> " " <> List.to_string(vsn) <> ": "

          _ ->
            "" <> Atom.to_string(app) <> ": "
        end

      :undefined ->
        ""
    end
  end

  def format_location(opts) when is_list(opts) do
    Exception.format_file_line(Keyword.get(opts, :file), Keyword.get(opts, :line), " ")
  end
end
