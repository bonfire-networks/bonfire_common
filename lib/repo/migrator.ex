defmodule Bonfire.Repo.Migrator do
@moduledoc """
TODO: add such a migrator to app's supervision tree?
"""
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], [])
  end

  def init(_) do

    # Bonfire.Common.ReleaseTasks.startup_migrations()
    # Bonfire.Common.ReleaseTasks.migrate_repos()

    {:ok, nil}
  end

end
