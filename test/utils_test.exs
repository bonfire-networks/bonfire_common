defmodule Bonfire.Common.UtilsTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.Utils

  describe "apply_task(:await, ...)" do
    test "returns the result of a function that finishes in time" do
      assert {:ok, :done} = Utils.apply_task(:await, fn -> :done end, timeout: 5_000)
    end

    test "gives up on a function that takes too long, and kills it" do
      # the pid comes from the spawn, not from inside the function, because on a busy runner the timeout can expire before the function even starts
      assert {:error, :timeout} =
               Utils.apply_task(:await, fn -> Process.sleep(:infinity) end,
                 timeout: 50,
                 module: Bonfire.Common.PidReportingTask
               )

      # the runaway process must actually be gone, otherwise it keeps burning CPU forever (which is what an unguarded `Task.await/2` timeout would leave behind)
      assert_received {:task_pid, pid}
      refute Process.alive?(pid)
    end

    test "waits as long as it takes with `timeout: false`" do
      assert {:ok, :done} =
               Utils.apply_task(:await, fn -> Process.sleep(100) && :done end, timeout: false)
    end

    test "returns an error when the function crashes (for a caller trapping exits)" do
      # a linked task's crash normally takes the caller down with it, so only a
      # caller that traps exits can observe the `{:exit, reason}` branch
      Process.flag(:trap_exit, true)

      assert {:error, _} = Utils.apply_task(:await, fn -> raise "nope" end, timeout: 5_000)
    end
  end
end
