# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers.Tables.Queries do
  import Ecto.Query
  alias Pointers.Table

  def query(Table) do
    from(p in Table, as: :table)
  end

  def query(filters), do: filter(Table, filters)

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

  def filter(q, {:id, id}) when is_binary(id) do
    where(q, [table: p], p.id == ^id)
  end

  def filter(q, {:id, ids}) when is_list(ids) do
    where(q, [table: p], p.id in ^ids)
  end

  # what fields
  def filter(q, {:select, fields}) when is_list(fields) do
    select(q, ^fields)
  end
end
