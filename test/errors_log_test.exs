defmodule Bonfire.Common.ErrorsLogTest do
  @moduledoc """
  What an error's log line keeps when it is longer than Logger's `:truncate` budget: the exception's banner (its type and message) whole, then as many frames as fit.

  The banner is what says what went wrong, so it keeps up to half the budget even when the stacktrace needs more, and Logger trims the deepest frames instead. Before, a stacktrace longer than the budget left the banner its 200-character floor, which cut the message mid-word.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Bonfire.Common.Errors

  test "an error whose stacktrace is longer than the budget still logs its whole message" do
    message = String.duplicate("word ", 120) <> "the end of the message"

    trace =
      for n <- 1..60,
          do:
            {Bonfire.Common.ErrorsLogTest.Deep, :"frame_#{n}", 1,
             [file: ~c"lib/deep.ex", line: n]}

    limit = Untangle.log_truncate_limit()
    assert is_integer(limit)

    # the case this is about: the message fits in half the budget, and the stacktrace alone is longer than the whole of it
    assert String.length(message) < div(limit, 2)
    assert String.length(Untangle.format_stacktrace(trace)) > limit

    log =
      capture_log(fn ->
        Errors.debug_log("Something failed", %RuntimeError{message: message}, trace, :error)
      end)

    assert log =~ "the end of the message"
    # and the frames nearest the error are still there
    assert log =~ "frame_1/1"
  end
end
