# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers.Queries do
  import Ecto.Query
  alias Pointers.Pointer
  import EctoSparkles
  import Untangle
  # alias Bonfire.Common.Utils
  alias Bonfire.Common
  alias Common.Types

  @behaviour Bonfire.Common.QueryModule
  def schema_module, do: Pointer

  def query(Pointer) do
    from(p in Pointer, as: :main_object)
    |> where([p], is_nil(p.deleted_at))

    # TODO: add filter to opt-in to including deleted ones
  end

  def query(filters), do: query(Pointer) |> query(filters)

  def query(nil, filters), do: filter(query(Pointer), filters)

  def query(q, filters), do: filter(query(q), filters)

  @spec filter(
          any,
          maybe_improper_list
          | {:id, binary | maybe_improper_list}
          | {:table, binary | [atom | binary]}
        ) :: any
  @doc "Filter the query according to arbitrary criteria"
  def filter(q, filter_or_filters)

  ## by many

  def filter(q, filters) when is_list(filters) do
    Enum.reduce(filters, q, &filter(&2, &1))
  end

  ## by fields

  def filter(q, {:id, id}) when not is_list(id) do
    case Types.ulid(id) do
      id when is_binary(id) ->
        where(q, [main_object: p], p.id == ^id)

      _ ->
        throw(error("Invalid ID"))
    end
  end

  def filter(q, {:id, ids}) when is_list(ids) do
    where(q, [main_object: p], p.id in ^Types.ulids(ids))
  end

  def filter(q, {:username, username}) when is_binary(username) do
    q
    |> proload([:profile, character: [:peered]])
    |> where([character: character], character.username == ^username)
  end

  def filter(q, {:canonical_uri, canonical_uri})
      when is_binary(canonical_uri) do
    q
    |> proload(peered: [:peer])
    |> where([peered: peered], peered.canonical_uri == ^canonical_uri)
  end

  def filter(q, {:table, id}) when is_binary(id),
    do: where(q, [main_object: p], p.table_id == ^id)

  def filter(q, {:table, name}) when is_atom(name),
    do: filter(q, {:table, Pointers.Tables.id!(name)})

  def filter(q, {:table, tables}) when is_list(tables) do
    tables = Pointers.Tables.ids!(tables)
    where(q, [main_object: p], p.table_id in ^tables)
  end

  # what fields
  def filter(q, {:select, fields}) when is_list(fields) do
    select(q, ^fields)
  end

  def filter(q, filter) do
    warn(filter, "Unknown filter")
    q
  end
end
