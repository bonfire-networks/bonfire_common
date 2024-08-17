defmodule Bonfire.Common.RepoTemplate do
  @moduledoc """
  Common functions useful in Ecto Repos
  """

  use Arrows

  defmacro __using__(_) do
    quote do
      alias Bonfire.Common.Config
      import Config, only: [repo: 0]
      alias Bonfire.Common.Utils
      alias Bonfire.Common.Types
      alias Bonfire.Common.Errors

      use Ecto.Repo,
        otp_app: Config.get(:umbrella_otp_app) || Config.get!(:otp_app),
        adapter: Ecto.Adapters.Postgres

      import Ecto.Query
      import Untangle
      use Arrows

      alias Needle.Changesets
      alias Needle.Pointer

      alias Ecto.Changeset

      @default_cursor_fields [cursor_fields: [{:id, :desc}]]

      def default_repo_opts,
        do: [timeout: Config.get([Bonfire.Common.Repo, :timeout], 20000)] |> debug()

      # def default_options(:all) do
      #   [
      #     returning: true
      #   ]
      # end

      @doc """
      Run a transaction, similar to `Repo.transaction/1`, but it expects an ok or error
      tuple. If an error tuple is returned, the transaction is aborted.

      ## Examples

          iex> transact_with(fn -> {:ok, "success"} end)
          "success"

          iex> transact_with(fn -> {:error, "failure"} end)
          ** (Ecto.RollbackError) Rolling back the DB transaction, error reason: failure

      """
      @spec transact_with(fun :: (-> {:ok, any} | {:error, any})) ::
              {:ok, any} | {:error, any}
      def transact_with(fun, opts \\ [])

      def transact_with(fun, opts) do
        transaction(
          fn ->
            ret = fun.()

            case ret do
              :ok -> :ok
              {:ok, v} -> v
              {:error, reason} -> rollback_error(reason)
              {:error, reason, extra} -> rollback_error(reason, extra)
              _ -> rollback_unexpected(ret)
            end
          end,
          opts
        )
      rescue
        exception in Postgrex.Error ->
          rollback("transact_with_unexpected_case")
          handle_postgrex_exception(exception, __STACKTRACE__)
      end

      # def transact_with(fun, opts) do
      #   transaction(fn ->
      #     case fun.() do
      #       {:ok, val} -> val
      #       {:error, val} -> rollback(val)
      #       val -> val # naughty
      #     end
      #   end, opts)
      # end

      @doc """
      Like `insert/1`, but understands remapping changeset errors to attr
      names from config (and only config, no overrides at present!)

      ## Examples

          iex> changeset = %Ecto.Changeset{valid?: false}
          iex> put(changeset)
          {:error, %Ecto.Changeset{}}
      """
      def put(%Changeset{} = changeset) do
        with {:error, changeset} <- insert(changeset) do
          Changesets.rewrite_constraint_errors(changeset)
        end
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__)
      end

      @doc """
      Like `put/1` but for multiple `changesets`

      ## Examples

          iex> changesets = [%{valid?: true}, %{valid?: false}]
          iex> put_many(changesets)
          {:error, [%{valid?: false}]}

          iex> changesets = [%{valid?: true}, %{valid?: true}]
          iex> put_many(changesets)
          {:ok, _result}
      """
      def put_many(things) do
        case Enum.filter(things, fn {_, %Changeset{valid?: v}} -> not v end) do
          [] -> transact_with(fn -> put_many(things, %{}) end)
          failed -> {:error, failed}
        end
      end

      defp put_many([], acc), do: {:ok, acc}

      defp put_many([{k, v} | is], acc) do
        case insert(v) do
          {:ok, v} -> put_many(is, Map.put(acc, k, v))
          {:error, other} -> {:error, {k, other}}
        end
      end

      @doc """
      Inserts or updates data in the database with upsert semantics.

      * `cs` - The changeset or schema to insert or update.
      * `keys_or_attrs_to_update` - A list of keys or a map of attributes to update.
      * `conflict_target` - The column(s) or constraint to check for conflicts, defaults to `[:id]`.

      ## Examples

          iex> upsert(%Ecto.Changeset{}, [:field1, :field2])
          {:ok, _result}

          iex> upsert(%Ecto.Changeset{}, %{field1: "value"})
          {:ok, _result}
      """
      def upsert(cs, keys_or_attrs_to_update \\ nil, conflict_target \\ [:id])

      def upsert(cs, attrs, conflict_target)
          when is_map(attrs) do
        upsert(cs, Map.to_list(attrs), conflict_target)
      end

      def upsert(cs, keys, conflict_target)
          when (is_list(keys) and is_struct(cs)) or is_atom(cs) do
        debug(keys, "update keys")

        keys =
          if not Keyword.keyword?(keys) do
            Enum.map(keys, &{&1, Needle.Changesets.get_field(cs, &1)})
          else
            keys
          end

        insert_or_update(
          cs,
          # on_conflict: {:replace_all_except, conflict_target},
          on_conflict: [set: keys],
          conflict_target: conflict_target
        )
      end

      def upsert(cs, nil, conflict_target) do
        insert_or_update(
          cs,
          on_conflict: :nothing
          # conflict_target: conflict_target
        )
      end

      @doc """
      Insert or update all entries with upsert semantics.

      * `schema` - The schema or table name to insert or update.
      * `data` - A list of maps containing the data to insert or update.
      * `conflict_target` - The column(s) or constraint to check for conflicts, defaults to `[:id]`.

      ## Examples

          iex> upsert_all(User, [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}])
          {:ok, _result}

          iex> upsert_all(User, [%{id: 1, name: "Alice Updated"}], [:id])
          {:ok, _result}
      """
      def upsert_all(schema, data, conflict_target \\ [:id]) when is_atom(schema) do
        insert_all(
          schema,
          data,
          on_conflict: {:replace_all_except, conflict_target},
          conflict_target: conflict_target
        )
      end

      @doc """
      Insert or ignore a changeset or struct into a schema.

      ## Examples

          iex> insert_or_ignore(%Ecto.Changeset{})
          {:ok, _result}

          iex> insert_or_ignore(%MySchema{field: "value"})
          {:ok, _result}

      """
      def insert_or_ignore(cs_or_struct) when is_struct(cs_or_struct) or is_atom(cs_or_struct) do
        cs_or_struct
        # FIXME?
        |> Map.put(:repo_opts, on_conflict: :ignore)
        # |> debug()
        |> insert(on_conflict: :nothing)
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__, exception)

        exception in Ecto.ConstraintError ->
          handle_postgrex_exception(exception, __STACKTRACE__, exception)
      end

      @doc """
      Insert or ignore a map (or iterate over a list of maps) into a schema.

      ## Examples

          iex> insert_or_ignore(MySchema, %{field: "value"})
          [{:ok, _result}]

          iex> insert_or_ignore(MySchema, [%{field: "value1"}, %{field: "value2"}])
          [{:ok, _result}]
      """
      def insert_or_ignore(schema, object) when is_map(object) do
        struct(schema, object)
        |> insert_or_ignore()
      end

      def insert_or_ignore(schema, objects) when is_list(objects) do
        Enum.map(objects, &insert_or_ignore(schema, &1))
      end

      @doc """
      Insert all or ignore a list of maps into a schema.

      ## Examples

          iex> insert_all_or_ignore(MySchema, [%{field: "value1"}, %{field: "value2"}])
          {:ok, _result}
      """
      def insert_all_or_ignore(schema, data) when is_atom(schema) do
        insert_all(schema, data, on_conflict: :nothing)
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__, exception)
      end

      @doc """
      Execute a query for one result and return either an `{:ok, result}` or `{:error, :not_found}` tuple.

      ## Examples

          iex> single(from u in User, where: u.id == 1)
          {:ok, %User{}}

          iex> single(from u in User, where: u.id == 999)
          {:error, :not_found}
      """
      def single(q) do
        one(limit(q, 1)) |> ret_single()
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__, {:error, :not_found})
      end

      @doc """
      Execute a query for one result and return either a result or a fallback value (`nil` by default).

      ## Examples

          iex> maybe_one(from u in User, where: u.id == 1)
          %User{}

          iex> maybe_one(from u in User, where: u.id == 999, "fallback")
          "fallback"
      """
      def maybe_one(q, fallback \\ nil) do
        one(limit(q, 1))
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__, fallback)

        e in DBConnection.ConnectionError ->
          error(
            e,
            "DB Connection error prevented a database query, returning a fallback"
          )

          fallback

        e in RuntimeError ->
          error(
            e,
            "Runtime error when attempting a database query, returning a fallback"
          )

          fallback

        e in ArgumentError ->
          error(
            e,
            "Argument error when attempting a database query, returning a fallback"
          )

          fallback
      end

      defp ret_single(nil), do: {:error, :not_found}
      defp ret_single(other), do: {:ok, other}

      @doc """
      Like `single/1`, except on failure, adds an error to the changeset.

      ## Examples

          iex> changeset = %Ecto.Changeset{}
          iex> find(from u in User, where: u.id == 1, changeset)
          {:ok, %User{}}

          iex> changeset = %Ecto.Changeset{}
          iex> find(from u in User, where: u.id == 999, changeset)
          {:error, %Ecto.Changeset{}}
      """
      def find(q, changeset, field \\ :form), do: ret_find(one(q), changeset, field)

      defp ret_find(nil, changeset, field),
        do: {:error, Changeset.add_error(changeset, field, "not_found")}

      defp ret_find(other, _changeset, _field), do: {:ok, other}

      @doc """
      Execute a query for one result where the primary key matches the given id, and return either an {:ok, result} tuple or a {:error, :not_found}.

      ## Examples

          iex> fetch(User, 1)
          {:ok, %User{}}

          iex> fetch(User, 999)
          {:error, :not_found}
      """
      @spec fetch(atom, integer | binary) :: {:ok, atom} | {:error, :not_found}
      def fetch(queryable, id) do
        case get(queryable, id) do
          nil -> {:error, :not_found}
          thing -> {:ok, thing}
        end
      end

      @doc """
      Execute a query for one result (using a keyword list to specify the key/value to query with), and return either an {:ok, result} tuple or a {:error, :not_found}.

      ## Examples

          iex> fetch_by(User, name: "Alice")
          {:ok, %User{}}

          iex> fetch_by(User, name: "Nonexistent")
          {:error, :not_found}
      """
      def fetch_by(queryable, term) do
        case get_by(queryable, term) do
          nil -> {:error, :not_found}
          thing -> {:ok, thing}
        end
      end

      @doc """
      Execute a query for multiple results given one or multiple IDs.

      ## Examples

          iex> fetch_all(User, [1, 2, 3])
          [%User{}, %User{}, %User{}]

          iex> fetch_all(User, 999)
          []
      """
      def fetch_all(queryable, id_or_ids) do
        queryable
        |> where([t], t.id in ^List.wrap(id_or_ids))
        |> all()
      end

      defp pagination_defaults,
        do: [
          # sets the default limit 
          limit: Bonfire.Common.Config.get(:default_pagination_limit, 10),
          # sets the maximum limit 
          maximum_limit: Config.get(:pagination_hard_max_limit, 500),
          # include total count by default?
          include_total_count: false,
          # sets the total_count_primary_key_field to uuid for calculating total_count
          total_count_primary_key_field: Needle.ULID
        ]

      defp paginator_paginate(
             queryable,
             opts \\ @default_cursor_fields,
             repo_opts \\ default_repo_opts()
           )

      defp paginator_paginate(queryable, opts, repo_opts) when is_list(opts) do
        merged_opts =
          Keyword.merge(
            pagination_defaults(),
            Keyword.merge(
              @default_cursor_fields,
              Keyword.merge(
                Utils.to_options(opts),
                Keyword.new(
                  if is_list(opts[:paginate]) or is_map(opts[:paginate]),
                    do: opts[:paginate],
                    else: opts[:paginated] || opts[:pagination] || []
                )
              )
            )
          )
          |> Keyword.update(:limit, 10, fn existing_value ->
            existing_value = Types.maybe_to_integer(existing_value)

            if is_number(opts[:multiply_limit]),
              do: ceil(existing_value * opts[:multiply_limit]),
              else: existing_value
          end)

        if opts[:return] == :query or merged_opts[:return] == :query do
          Paginator.paginated_query(queryable, merged_opts)
        else
          Paginator.paginate(queryable, merged_opts, __MODULE__, repo_opts)
        end
      end

      defp paginator_paginate(queryable, opts, repo_opts)
           when is_map(opts) and not is_struct(opts) do
        # info(opts, "opts")
        paginator_paginate(queryable, Utils.to_options(opts), repo_opts)
      end

      defp paginator_paginate(queryable, _, repo_opts) do
        paginator_paginate(queryable, @default_cursor_fields, repo_opts)
      end

      @doc """
      Different implementation for pagination using Scrivener (used by eg. rauversion).

      ## Examples

          iex> paginate(User, page: 1, page_size: 10)
          %Scrivener.Page{}
      """
      def paginate(pageable, options \\ []) do
        Scrivener.paginate(
          pageable,
          Scrivener.Config.new(__MODULE__, [page_size: 10], options)
        )
      end

      @doc """
      Execute a query for multiple results and return one page of results.
      This uses the main implementation for pagination, which is cursor-based and powered by the `Paginator` library.

      ## Examples

          iex> many_paginated(User, [limit: 10])
          %Paginator.Page{}
      """
      def many_paginated(queryable, opts \\ [], repo_opts \\ default_repo_opts())

      def many_paginated(%{order_bys: order} = queryable, opts, repo_opts)
          when is_list(order) and length(order) > 0 do
        # info(opts, "opts")
        debug(order, "order_bys")
        paginator_paginate(queryable, opts, repo_opts)
      end

      def many_paginated(queryable, opts, repo_opts) do
        # info(opts, "opts")
        queryable
        |> order_by([o],
          desc: o.id
        )
        |> paginator_paginate(opts, repo_opts)
      end

      @doc """
      Execute a query for multiple results and return the results.

      ## Examples

          iex> many(from u in User)
          [%User{}, %User{}]

          iex> many(from u in User, return: :query)
          #Ecto.Query<...>
      """
      def many(query, opts \\ []) do
        if opts[:return] == :query, do: query, else: all(query, opts)
      rescue
        exception in Postgrex.Error ->
          handle_postgrex_exception(exception, __STACKTRACE__, [])

        e in RuntimeError ->
          error(e, "Could not fetch list from database")
          []
      end

      @doc """
      Select and return only specific fields (specified as an atom or list of atoms)

      ## Examples
          > pluck(:id)
          [id1, id2]

          > pluck([:id, :inserted_at])
          [%{id: id1, inserted_at: _}, %{id: id2, inserted_at: _}]
      """
      def pluck(query, fields, opts \\ [])

      def pluck(query, field, opts) when is_atom(field) do
        query |> select(^[field]) |> many(opts) |> Enum.map(&Map.get(&1, field))
      end

      def pluck(query, fields, opts) when is_list(fields) do
        query |> select(^fields) |> many(opts) |> Enum.map(&Map.take(&1, fields))
      end

      @doc """
      Execute a query to delete all matching records.

      ## Examples

          iex> delete_many(from u in User, where: u.id < 100)
          {:ok, _count}
      """
      def delete_many(query) do
        query
        |> Ecto.Query.exclude(:order_by)
        |> delete_all()
      end

      defp handle_postgrex_exception(exception, stacktrace, fallback \\ false, changeset \\ nil)

      defp handle_postgrex_exception(
             %{postgres: %{code: :undefined_file} = pg},
             _,
             nil,
             fallback
           ) do
        error(
          pg,
          "Database error, probably a missing extension (eg. if using geolocation, you need to run Postgis)"
        )

        if fallback != false, do: fallback, else: {:error, :missing_db_extension}
      end

      # defp handle_postgrex_exception(
      #        %{postgres: %{code: :integrity_constraint_violation}},
      #        _,
      #        fallback, changeset
      #      ) do
      #   {:error, %{changeset | valid?: false}}
      # end

      defp handle_postgrex_exception(exception, stacktrace, fallback, _) do
        Errors.debug_exception(
          Utils.e(exception, :message, "A database error occurred"),
          exception,
          stacktrace
        )

        if fallback != false, do: fallback, else: reraise(exception, stacktrace)
      end

      defp rollback_error(reason, extra \\ nil) do
        error(reason, "Rolling back the DB transaction, error reason")
        if extra, do: info(extra, "Rolling back the DB transaction, error extra details")
        rollback(reason)
      end

      defp rollback_unexpected(ret) do
        error(
          ret,
          "Rolling back the DB transaction, because transaction expected one of `:ok` `{:ok, value}` `{:error, reason}` `{:error, reason, extra}` but got"
        )

        rollback("transact_with_unexpected_case")
      end

      def transact_many([]), do: {:ok, []}

      def transact_many(queries) when is_list(queries) do
        transaction(fn -> Enum.map(queries, &transact/1) end)
      end

      defp transact({:all, q}), do: many(q)
      defp transact({:count, q}), do: aggregate(q, :count)
      defp transact({:one, q}), do: one(q)

      defp transact({:one!, q}) do
        {:ok, ret} = single(q)
        ret
      end

      @doc """
      Executes raw SQL query.

      ## Examples

          > YourModule.sql("SELECT * FROM pointers")
      """
      def sql(raw_sql, data \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query!(__MODULE__, raw_sql, data, opts)
      end

      # def to_sql_raw(sql, kind \\ :all) do
      #   case to_sql(kind, sql) do
      #     {query, params} -> EctoSparkles.Log.inline_params(query, Map.new(params))
      #   end
      # end

      def make_subquery(query) do
        query
        |> Ecto.Query.exclude(:preload)
        |> subquery()
      end

      @doc """
      Can be used to log specific queries (by calling function) in production.

      ## Examples

          iex> trace(fn -> Repo.all(User) end)
          [%User{}, %User{}]
      """
      def trace(fun) when is_function(fun, 0) do
        prefix = config()[:telemetry_prefix]

        this_process = self()

        ref = make_ref()

        # here we're attaching a handler to the query event. When the query is performed in the same process as called this function
        # we want to basically "export" those values out to a list for investigation. Handlers are global though, so we need to
        # only `send` when we are in the current process.
        :telemetry.attach(
          "__help__",
          prefix ++ [:query],
          fn _, measurements, metadata, _config ->
            if self() == this_process do
              send(this_process, {ref, %{measurements: measurements, metadata: metadata}})
            end
          end,
          %{}
        )

        result = transaction(fun)

        :telemetry.detach("__help__")

        do_get_trace_messages(ref)

        result
      end

      defp do_get_trace_messages(ref) do
        receive do
          {^ref, %{metadata: metadata, measurements: measurements} = message} ->
            EctoSparkles.Log.handle_event(nil, measurements, metadata, nil)
            [message | do_get_trace_messages(ref)]

          {^ref, message} ->
            info(message)
            [message | do_get_trace_messages(ref)]
        after
          0 -> []
        end
      end

      @doc """
      Add an `ilike` clause to a query if the user query is safe.

      ## Examples

          iex> maybe_where_ilike(Needle.Pointer, :id, "Alice")
          #Ecto.Query<...>

          iex> maybe_where_ilike(Needle.Pointer, :id, "Al%ice")
          Needle.Pointer 
          # ^ unchanged due to unsafe query
      """
      def maybe_where_ilike(query, field, user_query, system_prefix \\ "", system_suffix \\ "") do
        case String.contains?(user_query, ["\\", "%", "_"]) do
          true ->
            error(user_query, "unsafe user query, skip clause")
            query

          false ->
            name_pattern = "#{system_prefix}#{user_query}#{system_suffix}"

            query
            |> where(ilike(^field, ^name_pattern))
        end
      end

      defdelegate maybe_preload(obj, preloads, opts \\ []),
        to: Bonfire.Common.Repo.Preload

      defdelegate preload_all(obj, opts \\ []),
        to: Bonfire.Common.Repo.Preload

      defdelegate preload_mixins(obj, opts \\ []),
        to: Bonfire.Common.Repo.Preload
    end
  end
end
