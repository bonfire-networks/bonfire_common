defmodule Bonfire.Common.PidReportingTask do
  @moduledoc """
  A stand-in for `Task` to pass as `module:` to `Bonfire.Common.Utils.apply_task/3`. It sends `{:task_pid, pid}` to the caller as soon as the task is spawned, so a test gets the task pid without depending on when (or whether) the task's function starts running.
  """

  def async(fun) do
    task = Task.async(fun)
    send(self(), {:task_pid, task.pid})
    task
  end
end
