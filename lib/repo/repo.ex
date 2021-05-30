defmodule Bonfire.Repo do
  @moduledoc """
  Ecto Repo and related common functions
  """

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils

  use Ecto.Repo,
    otp_app: Bonfire.Common.Config.get!(:otp_app),
    adapter: Ecto.Adapters.Postgres

  alias Pointers.Changesets
  alias Ecto.Changeset
  import Ecto.Query

  # import cursor-based pagination helper
  use Paginator,
    limit: 10,                           # sets the default limit TODO: put in config
    maximum_limit: 1000,                  # sets the maximum limit TODO: put in config
    include_total_count: false,           # include total count by default?
    total_count_primary_key_field: Pointers.ULID # sets the total_count_primary_key_field to uuid for calculating total_count

  require Logger

  # @doc """
  # Dynamically loads the repository url from the
  # DATABASE_URL environment variable.
  # """
  # def init(_, opts) do
  #   {:ok, Keyword.put(opts, :url, System.get_env("DATABASE_URL"))}
  # end

  @doc """
  Run a transaction, similar to `Repo.transaction/1`, but it expects an ok or error
  tuple. If an error tuple is returned, the transaction is aborted.
  """
  @spec transact_with(fun :: (() -> {:ok, any} | {:error, any})) :: {:ok, any} | {:error, any}
  def transact_with(fun) do
    transaction(fn ->
      ret = fun.()

      case ret do
        :ok -> :ok
        {:ok, v} -> v
        {:error, reason} -> rollback_error(reason)
        {:error, reason, extra} -> rollback_error(reason, extra)
        _ -> rollback_unexpected(ret)
      end
    end)
  end

  # def transact_with(fun) do
  #   transaction fn ->
  #     case fun.() do
  #       {:ok, val} -> val
  #       {:error, val} -> rollback(val)
  #       val -> val # naughty
  #     end
  #   end
  # end

  @doc """
  Like `insert/1`, but understands remapping changeset errors to attr
  names from config (and only config, no overrides at present!)
  """
  def put(%Changeset{}=changeset) do
    with {:error, changeset} <- insert(changeset) do
      Changesets.rewrite_constraint_errors(changeset)
    end
  end

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

  def upsert(q) do
    insert!(
      q,
      on_conflict: :nothing
    )
  end

  @doc """
  Like Repo.one, but returns an ok/error tuple.
  """
  def single(q), do: do_single(one(q))

  defp do_single(nil), do: {:error, :not_found}
  defp do_single(other), do: {:ok, other}

  @doc """
  Like Repo.single, except on failure, adds an error to the changeset
  """
  def find(q, changeset, field \\ :form), do: do_find(one(q), changeset, field)

  defp do_find(nil, changeset, field),
    do: {:error, Changeset.add_error(changeset, field, "not_found")}
  defp do_find(other, _changeset, _field), do: {:ok, other}

  @doc "Like Repo.get, but returns an ok/error tuple"
  @spec fetch(atom, integer | binary) :: {:ok, atom} | {:error, :not_found}
  def fetch(queryable, id) do
    case get(queryable, id) do
      nil -> {:error, :not_found}
      thing -> {:ok, thing}
    end
  end

  @doc "Like Repo.get_by, but returns an ok/error tuple"
  def fetch_by(queryable, term) do
    case get_by(queryable, term) do
      nil -> {:error, :not_found}
      thing -> {:ok, thing}
    end
  end

  def fetch_all(queryable, ids) when is_binary(ids) do
    queryable
    |> where([t], t.id in ^ids)
    |> all()
  end

  @default_cursor_fields [cursor_fields: [:id]]

  def many_paginated(queryable, opts \\ @default_cursor_fields, repo_opts \\ [])

  def many_paginated(%{order_bys: order} = queryable, opts, repo_opts) when is_list(order) and length(order) > 0 do
    # IO.inspect(order_by: order)
    queryable
    |>
    paginate(Keyword.merge(@default_cursor_fields, opts), repo_opts)
  end

  def many_paginated(queryable, opts, repo_opts) do
    queryable
    |>
    order_by([o],
      desc: o.id
    )
    # |> IO.inspect
    |>
    paginate(Keyword.merge(@default_cursor_fields, opts), repo_opts)
  end

  defp rollback_error(reason, extra \\ nil) do
    Logger.debug(transact_with_error: reason)
    if extra, do: Logger.debug(transact_with_error_extra: extra)
    rollback(reason)
  end

  defp rollback_unexpected(ret) do
    Logger.error(
      "Repo transaction expected one of `:ok` `{:ok, value}` `{:error, reason}` `{:error, reason, extra}` but got: #{
        inspect(ret)
      }"
    )

    rollback("transact_with_unexpected_case")
  end

  def transact_many([]), do: {:ok, []}

  def transact_many(queries) when is_list(queries) do
    transaction(fn -> Enum.map(queries, &transact/1) end)
  end

  defp transact({:all, q}), do: all(q)
  defp transact({:count, q}), do: aggregate(q, :count)
  defp transact({:one, q}), do: one(q)

  defp transact({:one!, q}) do
    {:ok, ret} = single(q)
    ret
  end


  # def maybe_preload(obj, :context) do
  # # follow the context Pointer
  #   CommonsPub.Contexts.prepare_context(obj)
  # end

  def maybe_preload({:ok, obj}, preloads), do: {:ok, maybe_preload(obj, preloads)}
  def maybe_preload(obj, preloads) when is_struct(obj) or is_list(obj) do
    Logger.info("maybe_preload: trying to preload: #{inspect preloads}")

    # Bonfire.Common.Pointers.Preload.maybe_preload_pointers(preloads,
      maybe_do_preload(obj, preloads)
    # )
  rescue
    e ->
      Logger.warn("maybe_preload error: #{inspect e}")
      obj
  end

  def maybe_preload(obj, _) do
    Logger.info("maybe_preload: can only preload from struct or list of structs")

    obj
  end

  defp maybe_do_preload(%Ecto.Association.NotLoaded{}, _), do: nil

  defp maybe_do_preload(obj, preloads) when is_struct(obj) or is_list(obj) do
    repo().preload(obj, preloads)

  rescue
    e ->
      Logger.warn("maybe_do_preload error: #{inspect e}")
      obj
  end

  defp maybe_do_preload(obj, _), do: obj


  def maybe_preloads_per_schema(objects, path, preloads) when is_list(objects) and is_list(path) and is_list(preloads) do
    Logger.info("maybe_preloads_per_schema iterate list of preloads")
    Enum.reduce(preloads, objects, &maybe_preloads_per_schema(&2, path, &1))
  end

  def maybe_preloads_per_schema(objects, path, {schema, preloads}) when is_list(objects) do
    Logger.info("maybe_preloads_per_schema try schema: #{inspect schema} in path: #{inspect path} with preloads: #{inspect preloads}")

    with {_old, loaded} <- get_and_update_in(
      objects,
      [Access.all()] ++ Enum.map(path, &Access.key!(&1)),
      &{&1, maybe_preloads_per_schema(&1, {schema, preloads})})
    do
      loaded
      # |> IO.inspect(label: "preloaded")
    end
  end

  def maybe_preloads_per_schema(object, _, _), do: object

  def maybe_preloads_per_schema(%{__struct__: object_schema} = object, {schema, preloads}) when object_schema==schema do
    Logger.info("maybe_preloads_per_schema preloading schema: #{inspect schema}")
    maybe_do_preload(object, preloads)
    # TODO: make one preload per get_and_update_in to avoid n+1
  end

  def maybe_preloads_per_schema(object, _), do: object


end
