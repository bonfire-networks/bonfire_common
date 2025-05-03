defmodule Bonfire.Common.Repo do
  @moduledoc """
  Main Ecto Repo.

  Note: functions are defined in `Bonfire.Common.RepoTemplate`
  """
  use Bonfire.Common.Config
  use Bonfire.Common.RepoTemplate

  defmacro __using__(_opts) do
    quote do
      # import the repo() function
      import Bonfire.Common.Config, only: [repo: 0]

      # import ecto `from` etc
      import Ecto.Query

      # for `reusable_join` and `join_preload` helpers
      import EctoSparkles

      alias Ecto.Changeset

      alias Bonfire.Common.Repo

      import Untangle

      import Bonfire.Common.Repo.Filter
    end
  end

  def migrate, do: EctoSparkles.AutoMigrator.startup_migrations()
end
