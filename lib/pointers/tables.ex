# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Pointers.Tables do
  alias Pointers.Pointer
  alias Pointers.Table
  alias Pointers.NotFound
  alias Bonfire.Common.Pointers.Tables.Queries
  import Ecto.Query
  import Bonfire.Common.Config, only: [repo: 0]
  require Logger
  use OK.Pipe

  def one(id) when is_binary(id) do
    if Bonfire.Common.Utils.is_ulid?(id) do
      one(id: id)
    else
      {:error, :not_found}
    end
  end

  def one(filters), do: repo().single(Queries.query(Table, filters))

  def one!(filters), do: repo().one!(Queries.query(Table, filters))

  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Table, filters))}


  @doc """
  Retrieves the Table that a pointer points to
  Note: Throws an error if the table cannot be found
  """
  @spec table!(Pointer.t()) :: Table.t()
  def table!(%Pointer{table_id: id}), do: table!(id)
  def table!(schema_or_tablename_or_id), do: Pointers.Tables.table!(schema_or_tablename_or_id)

  def schema_or_table!(schema_or_tablename_or_id) do
    # TODO
    with {:ok, table} <- Pointers.Tables.table(schema_or_tablename_or_id) do
      table.schema || table.table
    else _e ->
      with {:ok, table} <- one(schema_or_tablename_or_id) do
        table.schema || table.table
      else _e ->
        raise NotFound
      end
    end
  end

  def table_fields(table) when is_binary(table) do
    with {:ok, %{rows: rows}} <- repo().query("SELECT column_name FROM information_schema.columns WHERE TABLE_NAME='#{table}'") do
      for [column] <- rows do
        String.to_atom(column) # naughty but limited to existing DB fields
      end
    end
  end

  @doc "Lists all Pointable Tables"
  def list_tables(source \\ :code)

  def list_tables(:code), do: Pointers.Tables.data()

  def list_tables(:db) do
    repo().many(Pointers.Table)
    |> Enum.reduce(%{}, fn t, acc ->
      Map.merge(acc, %{t.table => t})
    end)
  end

  def list_ids do
    many(select: [:id]) ~>> Enum.map(& &1.id)
  end

  def list_schemas() do
    tables = list_tables()

    Enum.reduce(tables, [], fn {_id, x}, acc ->
      Enum.concat(acc, [x.schema])
    end)
  end

  def list_tables_debug() do
    Enum.concat(list_tables_db_vs_code(), list_tables_code_vs_db())
    |> Enum.sort(:desc)
    |> Enum.dedup
  end

  defp list_tables_db_vs_code() do
    list_tables(:db)
    |> Enum.map(fn {name, t} ->
      with {:ok, p} <- Pointers.Tables.table(name) do
        if t.id == p.id do
          {:ok, name}
        else
          {:error, "Code and DB have differing IDs for the same table", name, p.id, t.id}
        end
      else e ->
        {:error, "Table present in DB but not in code", name}
      end
    end)
    |> Enum.sort(:desc)
  end


  defp list_tables_code_vs_db() do
    db_tables = list_tables(:db)

    list_tables(:code)
    |> Enum.map(fn {schema, p} when is_atom(schema) ->

      t = Map.get(db_tables, p.table)

      if not is_nil(t) do
        if t.id == p.id do
          {:ok, p.table}
        else
          {:error, "Code and DB have differing IDs for the same table", p.table, p.id, t.id}
        end
      else
        {:error, "Table present in code but not in DB", p.table}
      end

      _ -> nil
    end)
    |> Enum.sort(:desc)
    |> Enum.dedup
  end



end
