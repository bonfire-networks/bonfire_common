# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Repo.Revision do
  import Ecto.Query, only: [from: 2]

  @repo Application.get_env(:bonfire_common, :repo_module)

  def insert(module, parent, attrs) do
    parent_keys =
      parent
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)

    revision_attrs = Map.drop(attrs, parent_keys)

    parent
    |> module.create_changeset(revision_attrs)
    |> @repo.insert()
  end

  def preload(module, queryable) do
    query = from(r in module, order_by: [desc: r.inserted_at])
    @repo.preload(queryable, [:current, revisions: query])
  end
end
