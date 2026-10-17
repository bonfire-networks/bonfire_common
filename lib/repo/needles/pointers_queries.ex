# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Needles.Pointers.Queries do
  @moduledoc "Queries for `Needle` Pointers"

  use Bonfire.Common.Repo
  import Ecto.Query
  alias Needle.Pointer
  import EctoSparkles
  import Untangle
  # alias Bonfire.Common.Utils
  alias Bonfire.Common
  alias Common.Types

  @behaviour Bonfire.Common.QueryModule
  def schema_module, do: Pointer

  def query_base, do: from(p in Pointer, as: :main_object)
  def query_incl_deleted(), do: query_base()

  @doc "Pointers, without deleted ones unless `deleted: true`, and without future-dated (scheduled) ones unless `include_scheduled: true`. Each opt lifts only its own filter."
  def query_base(opts) do
    query_base()
    |> maybe_filter_deleted(opts)
    |> repo().maybe_filter_out_future_ulids(opts)
  end

  defp maybe_filter_deleted(query, opts) do
    if opts[:deleted], do: query, else: where(query, [p], is_nil(p.deleted_at))
  end

  def query(pointer_or_filters \\ Pointer)

  def query(Pointer), do: query_base([])

  def query(filters), do: filter(query(Pointer), filters)

  def query(nil, filters), do: filter(query(Pointer), filters)
  def query(Pointer, filters), do: filter(query(Pointer), filters)
  def query(q, filters), do: filter(q, filters)

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
    #  TODO: support prefixed UUIDs?
    case Types.uid(id) do
      id when is_binary(id) ->
        where(q, [main_object: p], p.id == ^id)

      _ ->
        throw(error("Invalid ID"))
    end
  end

  def filter(q, {:id, ids}) when is_list(ids) do
    where(q, [main_object: p], p.id in ^Types.uids(ids))
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
    do: filter(q, {:table, Needle.Tables.id!(name)})

  def filter(q, {:table, tables}) when is_list(tables) do
    tables = Needle.Tables.ids!(tables)
    where(q, [main_object: p], p.table_id in ^tables)
  end

  # deleted ones are left out unless `deleted: true`
  def filter(q, {:deleted, true}), do: q
  def filter(q, {:deleted, false}), do: where(q, [main_object: p], is_nil(p.deleted_at))

  # future-dated (scheduled) ones are left out unless `scheduled: true`
  def filter(q, {:scheduled, true}), do: q
  def filter(q, {:scheduled, false}), do: repo().maybe_filter_out_future_ulids(q)

  # what fields
  def filter(q, {:select, fields}) when is_list(fields) do
    select(q, ^fields)
  end

  def filter(q, filter) do
    warn(filter, "Unknown filter")
    q
  end
end
