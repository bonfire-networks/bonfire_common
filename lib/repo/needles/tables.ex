# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Needles.Tables do
  @moduledoc "Helpers for querying `Needle` types/tables"

  use Arrows
  import Ecto.Query
  import Bonfire.Common.Config, only: [repo: 0]

  alias Needle.Pointer
  alias Needle.Table
  alias Needle.NotFound
  alias Bonfire.Common.Needles.Tables.Queries
  import Untangle

  @doc """
  Retrieves a single record by ID or filters.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.one("valid_ulid")
      {:ok, %Table{}}

      iex> Bonfire.Common.Needles.Tables.one(%{field: "value"})
      %Table{}
  """
  def one(id) when is_binary(id) do
    if Bonfire.Common.Types.is_ulid?(id) do
      one(id: id)
    else
      {:error, :not_found}
    end
  end

  def one(filters), do: repo().single(Queries.query(Table, filters))

  @doc """
  Retrieves a single record by filters, raising an error if not found.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.one!(%{field: "value"})
      %Table{}
  """
  def one!(filters), do: repo().one!(Queries.query(Table, filters))

  @doc """
  Retrieves details of multiple tables based on filters.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.many(%{field: "value"})
      {:ok, [%Table{}]}
  """
  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Table, filters))}

  @doc """
  Retrieves the Table that a pointer points to.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.table!(%Pointer{table_id: "valid_id"})
      %Table{}

      iex> Bonfire.Common.Needles.Tables.table!("valid_id")
      %Table{}

      iex> Bonfire.Common.Needles.Tables.table!("invalid_id")
      # throws error
  """
  @spec table!(Pointer.t()) :: Table.t()
  def table!(%Pointer{table_id: id}), do: table!(id)

  def table!(schema_or_tablename_or_id),
    do: Needle.Tables.table!(schema_or_tablename_or_id)

  @doc """
  Retrieves the schema or table name.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.schema_or_table!("valid_id")
      MySchema

      iex> Bonfire.Common.Needles.Tables.schema_or_table!("table_name")
      MySchema
  """
  def schema_or_table!(schema_or_tablename_or_id) do
    # TODO
    with {:ok, table} <- Needle.Tables.table(schema_or_tablename_or_id) do
      table.schema || table.table
    else
      _e ->
        with {:ok, table} <- one(schema_or_tablename_or_id) do
          table.schema || table.table
        else
          _e ->
            raise NotFound
        end
    end
  end

  @doc """
  Retrieves fields of a table given a schema or table name.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.table_fields(MySchema)
      [:field1, :field2]

      iex> Bonfire.Common.Needles.Tables.table_fields("table_name")
      [:field1, :field2]
  """
  def table_fields(schema) when is_atom(schema), do: table_fields(schema.__schema__(:source))

  def table_fields(table) when is_binary(table) do
    with rows <-
           repo().many(
             from("columns",
               prefix: "information_schema",
               select: [:column_name],
               where: [table_name: ^table]
             )
           )
           |> debug() do
      for row <- rows do
        # naughty but limited to existing DB fields
        String.to_atom(row[:column_name])
      end
    end
  end

  @doc """
  Retrieves metadata about fields of a table given a schema or table name.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.table_fields_meta(MySchema)
      [%{column_name: "field1", data_type: "type", column_default: nil, is_nullable: "NO"}]

      iex> Bonfire.Common.Needles.Tables.table_fields_meta("table_name")
      [%{column_name: "field1", data_type: "type", column_default: nil, is_nullable: "NO"}]
  """
  def table_fields_meta(schema) when is_atom(schema),
    do: table_fields_meta(schema.__schema__(:source))

  def table_fields_meta(table) when is_binary(table) do
    repo().many(
      from("columns",
        prefix: "information_schema",
        select: [:column_name, :data_type, :column_default, :is_nullable],
        where: [table_name: ^table]
      )
    )
  end

  # def table_fields(table) when is_binary(table) do
  #   with {:ok, %{rows: rows}} <-
  #          repo().query(
  #            "SELECT column_name FROM information_schema.columns WHERE TABLE_NAME='#{table}'"
  #          ) do
  #     for [column] <- rows do
  #       # naughty but limited to existing DB fields
  #       String.to_atom(column)
  #     end
  #   end
  # end

  @doc """
  Lists all Pointable Tables.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.list_tables()
      [%Table{}]

      iex> Bonfire.Common.Needles.Tables.list_tables(:db)
      %{"table_name" => %Table{}}
  """
  def list_tables(source \\ :code)

  def list_tables(:code), do: Needle.Tables.data()

  def list_tables(:db) do
    repo().many(Needle.Table)
    |> Enum.reduce(%{}, fn t, acc ->
      Map.merge(acc, %{t.table => t})
    end)
  end

  @doc """
  Lists IDs of all Pointable Tables.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.list_ids()
      ["id1", "id2"]
  """
  def list_ids do
    many(select: [:id]) ~> Enum.map(& &1.id)
  end

  @doc """
  Lists schemas of all Pointable Tables.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.list_schemas()
      [:schema1, :schema2]
  """
  def list_schemas() do
    tables = list_tables()

    Enum.reduce(tables, [], fn {_id, x}, acc ->
      Enum.concat(acc, [x.schema])
    end)
  end

  @doc """
  Lists and debugs all Pointable Tables.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.list_tables_debug()
      [{:ok, "table1"}, {:error, "Code and DB have differing IDs for the same table", "table2", "id2a", "id2b"}, {:error, "Table present in DB but not in code", "table3"}]
  """
  def list_tables_debug() do
    Enum.concat(list_tables_db_vs_code(), list_tables_code_vs_db())
    |> Enum.sort(:desc)
    |> Enum.dedup()
  end

  defp list_tables_db_vs_code() do
    list_tables(:db)
    |> Enum.map(fn {name, t} ->
      with {:ok, p} <- Needle.Tables.table(name) do
        if t.id == p.id do
          {:ok, name}
        else
          {:error, "Code and DB have differing IDs for the same table", name, p.id, t.id}
        end
      else
        _e ->
          {:error, "Table present in DB but not in code", name}
      end
    end)
    |> Enum.sort(:desc)
  end

  defp list_tables_code_vs_db() do
    db_tables = list_tables(:db)

    list_tables(:code)
    |> Enum.map(fn
      {schema, p} when is_atom(schema) ->
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

      _ ->
        nil
    end)
    |> Enum.sort(:desc)
    |> Enum.dedup()
  end
end
