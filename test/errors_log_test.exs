defmodule Bonfire.Common.ErrorsLogTest do
  @moduledoc """
  What an error's log line keeps when it is longer than Logger's `:truncate` budget: the exception's banner (its type and message) whole, then as many frames as fit.

  The banner is what says what went wrong, so it keeps up to half the budget even when the stacktrace needs more, and Logger trims the deepest frames instead. Before, a stacktrace longer than the budget left the banner its 200-character floor, which cut the message mid-word.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Bonfire.Common.Errors

  @moduletag :backend

  # a budget of our own rather than the environment's (CI runs with `TEST_LOG_TRUNCATE=340`), since the case needs a message longer than the old 200-character floor that still fits in half the budget
  @budget 2000

  setup do
    truncate = Application.get_env(:logger, :truncate)
    console = Application.get_env(:logger, :console)

    Application.put_env(:logger, :truncate, @budget)
    Application.put_env(:logger, :console, Keyword.put(console || [], :truncate, @budget))

    on_exit(fn ->
      Application.put_env(:logger, :truncate, truncate)
      Application.put_env(:logger, :console, console)
    end)
  end

  test "an error whose stacktrace is longer than the budget still logs its whole message" do
    message = String.duplicate("word ", 120) <> "the end of the message"

    trace =
      for n <- 1..60,
          do:
            {Bonfire.Common.ErrorsLogTest.Deep, :"frame_#{n}", 1,
             [file: ~c"lib/deep.ex", line: n]}

    assert Untangle.log_truncate_limit() == @budget

    # the case this is about: the message is longer than the old floor but fits in half the budget, and the stacktrace alone is longer than the whole of it
    assert String.length(message) > 200
    assert String.length(message) < div(@budget, 2)
    assert String.length(Untangle.format_stacktrace(trace)) > @budget

    log =
      capture_log([truncate: @budget], fn ->
        Errors.debug_log("Something failed", %RuntimeError{message: message}, trace, :error)
      end)

    assert log =~ "the end of the message"
    # and the frames nearest the error are still there
    assert log =~ "frame_1/1"
  end
end
