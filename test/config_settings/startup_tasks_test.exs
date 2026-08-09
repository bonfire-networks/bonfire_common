defmodule Bonfire.Common.StartupTasksTest do
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.StartupTasks
  alias Bonfire.Common.Settings.IdCutoffs

  test "tasks/0 returns the modules registered under :run (the real, deep-merged registry)" do
    # IdCutoffs registers itself in bonfire_common's RuntimeConfig — the live registration must resolve
    # to a module (regression: a bare-atom `run: [Mod]` list left tasks/0 returning [])
    assert IdCutoffs in StartupTasks.tasks(),
           "expected IdCutoffs among registered startup tasks, got: #{inspect(StartupTasks.tasks())}"
  end

  test "tasks/0 extracts the module values and drops keys set falsy (unregistered)" do
    original = Application.get_env(:bonfire_common, StartupTasks)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:bonfire_common, StartupTasks)
        v -> Application.put_env(:bonfire_common, StartupTasks, v)
      end
    end)

    Application.put_env(:bonfire_common, StartupTasks, run: [a: SomeTask, b: false, c: OtherTask])
    assert StartupTasks.tasks() == [SomeTask, OtherTask]
  end
end
