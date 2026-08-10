defmodule Bonfire.Common.StartupTasks do
  @moduledoc """
  Single supervised entry-point for one-shot startup tasks (`Bonfire.Common.StartupTask`) that must run AFTER instance Settings are loaded into Config by `Bonfire.Common.Settings.LoadInstanceConfig`, e.g.
  recording ID cutoffs (`Bonfire.Common.Settings.IdCutoffs`), and one-off data rollouts.

  Added to the supervision tree ONCE (right after `LoadInstanceConfig`) so new tasks need no further wiring, a task registers itself under a named key in the `:run` keyword list (keyword lists deep-merge across `config` declarations, so any extension adds its own without clobbering others'; set a key to `false` to unregister):

      config :bonfire_common, Bonfire.Common.StartupTasks, run: [id_cutoffs: Bonfire.Common.Settings.IdCutoffs]

  Runs each registered task in `handle_continue`, i.e. AFTER `init/1` returns, so it NEVER blocks the rest of boot: sequentially, each guarded so one failing (or slow) task can neither break boot nor stop the others. A heavy task (e.g. a multi-million-row backfill) therefore runs in the background here while the app is already serving; it must be idempotent + self-gated (see `StartupTask`).

  Uses `restart: :transient` plus a clean `:stop` means it isn't restarted once its tasks have run.
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

  @doc "Runs every registered startup task (see `tasks/0`), each guarded. Runs in every env, each task decides for itself whether it should do anything in the current env."
  def run_all do
    case tasks() do
      [] ->
        :ok

      mods ->
        Logger.info("Running #{length(mods)} startup task(s): #{inspect(mods)}")
        Enum.each(mods, &run_task/1)
    end

    :ok
  end

  @doc "The registered startup-task modules (the truthy values of the `:run` keyword list)."
  def tasks, do: for({_name, mod} <- Config.get([__MODULE__, :run], []), mod, do: mod)

  defp run_task(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :run, 0) do
      mod.run()
      Logger.info("Startup task #{inspect(mod)} completed")
    else
      Logger.error("Startup task #{inspect(mod)} does not implement run/0 — skipping")
    end
  rescue
    e ->
      Logger.error(
        "Startup task #{inspect(mod)} failed (will retry next boot): " <>
          Exception.format(:error, e, __STACKTRACE__)
      )
  end
end
