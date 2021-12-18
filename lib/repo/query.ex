# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Repo.Query do
  import Ecto.Query
  # import Bonfire.Common.Config, only: [repo: 0]

  defmacro __using__(opts) do

    # Always define filters for the `id` field
    searchable_fields = (opts[:searchable_fields] || []) ++ [:id]

    # Always define a sorter for the `id` field
    sortable_fields = (opts[:sortable_fields] || []) ++ [:id]

    # Use a default per page of `20`, but allow the user to change this value
    # default_per_page = opts[:default_per_page] || 20

    # Allow the user to include extra plugins
    extra_plugins = opts[:plugins] || []

    #IO.inspect(Keyword.get(opts, :schema))

    quote do
      # import the repo() function
      import Bonfire.Common.Config, only: [repo: 0]

      # import ecto `from` etc
      import Ecto.Query

      # `reusable_join` and `join_preload` helpers
      import EctoSparkles

      require Logger

    end
  end

  def unroll(items, key \\ :context)
  def unroll(items, key) when is_list(items), do: Enum.map(items, &unroll(&1, key))
  def unroll({l, r}, key), do: %{l | key => r}

  def filter(q, {:username, username}) when is_binary(username) do
    where(q, [a], a.preferred_username == ^username)
  end

  def filter(q, {:username, usernames}) when is_list(usernames) do
    where(q, [a], a.preferred_username in ^usernames)
  end

  def order_by_recently_updated(query) do
    order_by(query, desc: :updated_at)
  end

  defmacro match_admin() do
    quote do
      %{
        instance_admin: %{is_instance_admin: true}
      }
    end
  end
end
