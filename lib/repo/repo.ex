defmodule Bonfire.Common.Repo do
  @moduledoc """
  Ecto Repo and related common functions
  """
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
    end
  end
end
