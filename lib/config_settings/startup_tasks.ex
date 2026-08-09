defmodule Bonfire.Common.StartupTasks do
  @moduledoc """
  Single supervised entry-point for one-shot startup tasks (`Bonfire.Common.StartupTask`) that must run AFTER instance Settings are loaded into Config by `Bonfire.Common.Settings.LoadInstanceConfig`, e.g.
  recording ID cutoffs (`Bonfire.Common.Settings.IdCutoffs`), and one-off data rollouts.

  Added to the supervision tree ONCE (right after `LoadInstanceConfig`) so new tasks need no further wiring, a task registers itself by declaring its module in config (a keyword list, so declarations from any extension deep-merge; set a module to `false` to unregister):

      config :bonfire_common, Bonfire.Common.StartupTasks, run: [Bonfire.Common.Settings.IdCutoffs]

  Runs each registered task in `handle_continue`, i.e. AFTER `init/1` returns, so it NEVER blocks the rest of boot: sequentially, each guarded so one failing (or slow) task can neither break boot nor stop the others. A heavy task (e.g. a multi-million-row backfill) therefore runs in the background here while the app is already serving; it must be idempotent + self-gated (see `StartupTask`).

  Skipped in the `:test` env (tasks that need test coverage are called directly). `restart: :transient` plus a clean `:stop` means it isn't restarted once its tasks have run.
  """
  use GenServer, restart: :transient
  require Logger
  use Bonfire.Common.Config

  @spec start_link(ignored :: term) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  @impl true
  def init(_), do: {:ok, [], {:continue, :run}}

  @impl true
  def handle_continue(:run, state) do
    run_all()
    {:stop, :normal, state}
  end

  @doc "Runs every registered startup task (see `tasks/0`), each guarded. Skipped in the `:test` env."
  def run_all do
    if Config.env() != :test do
      case tasks() do
        [] ->
          :ok

        mods ->
          Logger.info("Running #{length(mods)} startup task(s): #{inspect(mods)}")
          Enum.each(mods, &run_task/1)
      end
    end

    :ok
  end

  @doc "The registered startup-task modules (keys of the `:run` keyword list whose value is truthy)."
  def tasks, do: for({mod, truthy} <- Config.get([__MODULE__, :run], []), truthy, do: mod)

  defp run_task(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :run, 0) do
      mod.run()
    else
      Logger.error("StartupTask #{inspect(mod)} does not implement run/0 — skipping")
    end
  rescue
    e ->
      Logger.error(
        "StartupTask #{inspect(mod)} failed (will retry next boot): " <>
          Exception.format(:error, e, __STACKTRACE__)
      )
  end
end
