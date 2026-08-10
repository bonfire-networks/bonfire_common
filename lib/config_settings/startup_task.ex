defmodule Bonfire.Common.StartupTask do
  @moduledoc """
  Behaviour for a one-shot startup task run once per boot by `Bonfire.Common.StartupTasks`, AFTER
  instance Settings have been loaded into Config (see `Bonfire.Common.Settings.LoadInstanceConfig`).

  Register the implementing module in config (see `Bonfire.Common.StartupTasks`). A task MUST be:

    * idempotent: it re-runs on every boot until it records (e.g. in instance Settings) that its work
      is done, so running twice must be safe and converge;
    * self-gating + cheap-to-skip once done, as nothing external tracks "already ran"; the task decides. This includes deciding per ENV: the runner runs in every env, so a task that shouldn't act in tests must say so itself;
    * safe to fail: a raise is caught and logged by the runner (it must never break boot).

  Heavy work is fine: tasks run off the boot-blocking path (see `Bonfire.Common.StartupTasks`).
  """
  @callback run() :: any()
end
