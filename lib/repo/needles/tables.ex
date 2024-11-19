# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Needles.Tables do
  @moduledoc "Helpers for querying `Needle` types/tables"

  use Arrows
  use Bonfire.Common.E
  import Ecto.Query
  import Bonfire.Common.Config, only: [repo: 0]

  alias Needle.Pointer
  alias Needle.Table
  alias Needle.Tables
  alias Needle.NotFound
  alias Bonfire.Common.Needles.Tables.Queries
  import Untangle

  @doc """
  Retrieves a single record by ID or filters.

  ## Examples

      > Bonfire.Common.Needles.Tables.one("valid_ulid")
      {:ok, %Table{}}

      > Bonfire.Common.Needles.Tables.one(%{field: "value"})
      %Table{}
  """
  def one(id) when is_binary(id) do
    if Bonfire.Common.Types.is_uid?(id) do
      one(id: id)
    else
      {:error, :not_found}
    end
  end

  def one(filters), do: repo().single(Queries.query(Table, filters))

  @doc """
  Retrieves a single record by filters, raising an error if not found.

  ## Examples

      > Bonfire.Common.Needles.Tables.one!(%{field: "value"})
      %Table{}
  """
  def one!(filters), do: repo().one!(Queries.query(Table, filters))

  @doc """
  Retrieves details of multiple tables based on filters.

  ## Examples

      > Bonfire.Common.Needles.Tables.many(%{field: "value"})
      {:ok, [%Table{}]}
  """
  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Table, filters))}

  @doc """
  Retrieves the Table that a pointer points to.

  ## Examples

      > Bonfire.Common.Needles.Tables.table!(%Pointer{table_id: "valid_id"})
      %Table{}

      > Bonfire.Common.Needles.Tables.table!("valid_id")
      %Table{}

      > Bonfire.Common.Needles.Tables.table!("invalid_id")
      # throws error
  """
  @spec table!(Pointer.t()) :: Table.t()
  def table!(%Pointer{table_id: id}), do: table!(id)

  def table!(schema_or_tablename_or_id),
    do: Needle.Tables.table!(schema_or_tablename_or_id)

  @doc """
  Retrieves the schema or table name.

  ## Examples

      iex> Bonfire.Common.Needles.Tables.schema_or_table!("5EVSER1S0STENS1B1YHVMAN01D")
      Bonfire.Data.Identity.User

      iex> Bonfire.Common.Needles.Tables.schema_or_table!("bonfire_data_identity_user")
      Bonfire.Data.Identity.User
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

      > Bonfire.Common.Needles.Tables.table_fields(MySchema)
      [:field1, :field2]

      > Bonfire.Common.Needles.Tables.table_fields("table_name")
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

      > Bonfire.Common.Needles.Tables.table_fields_meta(MySchema)
      [%{column_name: "field1", data_type: "type", column_default: nil, is_nullable: "NO"}]

      > Bonfire.Common.Needles.Tables.table_fields_meta("table_name")
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

      iex> tables = Bonfire.Common.Needles.Tables.list_tables()

      iex> tables = Bonfire.Common.Needles.Tables.list_tables(:db)
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

      > Bonfire.Common.Needles.Tables.list_ids()
      ["id1", "id2"]
  """
  def list_ids do
    many(select: [:id]) ~> Enum.map(& &1.id)
  end

  @doc """
  Lists schemas of all Pointable Tables.

  ## Examples

      iex> schemas = Bonfire.Common.Needles.Tables.list_schemas()
      iex> true = Enum.member?(schemas, Needle.Table)
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

      > Bonfire.Common.Needles.Tables.list_tables_debug()
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

  @doc """
  Retrieves a list of schema mixins that aren't loaded in the given Ecto struct.

  ## Examples

      > schema_mixins(%Bonfire.Data.Identity.User{})
      [:account]
  """
  def schema_mixins_not_loaded(%type{} = struct) do
    mixin_modules = Tables.mixin_modules()

    for({key, %Ecto.Association.NotLoaded{}} <- Map.from_struct(struct), do: key)
    |> Enum.filter(&(&1 in mixin_modules))
  end

  @doc """
  Retrieves schema mixins for a given Ecto struct.

  ## Examples

      iex> schemas = schema_mixin_assocs(Bonfire.Data.Identity.User)
      iex> true = Enum.member?(schemas, :character)
  """
  def schema_mixin_assocs(%type{} = _structure), do: schema_mixin_assocs(type)

  def schema_mixin_assocs(type) do
    mixin_modules = Tables.mixin_modules()

    type.__schema__(:associations)
    |> Enum.filter(fn assoc ->
      case e(type.__schema__(:association, assoc), :queryable, nil) do
        nil -> false
        assoc_module -> assoc_module in mixin_modules
      end
    end)
  end

  @doc """
  Retrieves schema mixins for a given Ecto struct.

  ## Examples

      iex> schemas = schema_mixin_modules(Bonfire.Data.Identity.User)
      iex> true = Enum.member?(schemas, Bonfire.Data.Identity.Character)
  """
  def schema_mixin_modules(%type{} = _structure), do: schema_mixin_modules(type)

  def schema_mixin_modules(type) do
    mixin_modules = Tables.mixin_modules()

    type.__schema__(:associations)
    |> Enum.map(fn assoc ->
      e(type.__schema__(:association, assoc), :queryable, nil)
    end)
    |> Enum.reject(&is_nil/1)
    #  TODO: optimise?
    |> Enum.filter(&(&1 in mixin_modules))
  end

  @doc """
  Returns the module name of an association

  ## Examples

      iex> maybe_assoc_module(:character, Bonfire.Data.Identity.User)
      Bonfire.Data.Identity.Character

      iex> maybe_assoc_module(:non_existing_assoc_name, Bonfire.Data.Identity.User)
      nil
  """
  def maybe_assoc_module(assoc_name, parent_type)
      when is_atom(assoc_name) and is_atom(parent_type) do
    e(parent_type.__schema__(:association, assoc_name), :queryable, nil)
  end

  def maybe_assoc_module(_, _), do: false

  @doc """
  Returns the module name of an association if it represents a mixin by checking if it's listed in the parent schema's mixin associations.

  ## Examples

      iex> maybe_assoc_mixin_module(:character, Bonfire.Data.Identity.User)
      Bonfire.Data.Identity.Character

      iex> maybe_assoc_mixin_module(:non_existing_assoc_name, Bonfire.Data.Identity.User)
      nil
  """
  def maybe_assoc_mixin_module(assoc_name, parent_type)
      when is_atom(assoc_name) and is_atom(parent_type) do
    mixin_modules = Tables.mixin_modules()

    module = maybe_assoc_module(assoc_name, parent_type)

    if module in mixin_modules, do: module
  end

  def maybe_assoc_mixin_module(_, _), do: false

  @doc """
  Checks if a schema represents a mixin by checking if it's listed in the parent schema's mixin associations.

  ## Examples

      iex> module_mixin_of?(Bonfire.Data.Identity.Character, Bonfire.Data.Identity.User)
      true

      iex> module_mixin_of?(Needle.Table, Bonfire.Data.Identity.User)
      false
  """
  def module_mixin_of?(assoc_name, parent_type)
      when is_atom(assoc_name) and is_atom(parent_type) do
    schema_mixin_modules(parent_type)
    |> debug(inspect(parent_type))
    |> Enum.member?(assoc_name)
  end

  def module_mixin_of?(_, _), do: false

  @doc """
  Checks if a schema represents a mixin by checking if it's listed in the parent schema's mixin associations.

  ## Examples

      iex> assoc_mixin_of?(:character, Bonfire.Data.Identity.User)
      true

      iex> assoc_mixin_of?(:non_existing_assoc_name, Bonfire.Data.Identity.User)
      false
  """
  def assoc_mixin_of?(assoc_name, parent_type)
      when is_atom(assoc_name) and is_atom(parent_type) do
    schema_mixin_assocs(parent_type)
    |> debug(inspect(parent_type))
    |> Enum.member?(assoc_name)
  end

  def assoc_mixin_of?(_, _), do: false
end
