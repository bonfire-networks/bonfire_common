defmodule Bonfire.Repo do
  @moduledoc """
  Ecto Repo and related common functions
  """

  @repo Application.get_env(:bonfire_common, :repo_module)

  use Ecto.Repo,
    otp_app: Application.get_env(:bonfire_common, :otp_app),
    adapter: Ecto.Adapters.Postgres

  alias Pointers.Changesets
  alias Ecto.Changeset

  import Ecto.Query
  alias Bonfire.Common.Errors.NotFoundError

  require Logger

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
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
  names from config (and only config, no overrides at present!).
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

  @doc """
  Like Repo.one, but returns an ok/error tuple.
  """
  def single(q), do: do_single(one(q))

  defp do_single(nil), do: NotFoundError.new()
  defp do_single(other), do: {:ok, other}

  @doc "Like Repo.get, but returns an ok/error tuple"
  @spec fetch(atom, integer | binary) :: {:ok, atom} | {:error, NotFoundError.t()}
  def fetch(queryable, id) do
    case get(queryable, id) do
      nil -> {:error, NotFoundError.new()}
      thing -> {:ok, thing}
    end
  end

  @doc "Like Repo.get_by, but returns an ok/error tuple"
  def fetch_by(queryable, term) do
    case get_by(queryable, term) do
      nil -> {:error, NotFoundError.new()}
      thing -> {:ok, thing}
    end
  end

  def fetch_all(queryable, ids) when is_binary(ids) do
    queryable
    |> where([t], t.id in ^ids)
    |> all()
  end

  defp rollback_error(reason) do
    Logger.debug(transact_with_error: reason)
    rollback(reason)
  end

  defp rollback_unexpected(ret) do
    Logger.error(
      "Repo transaction expected one of `:ok` `{:ok, value}` `{:error, reason}` but got: #{
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

  def maybe_preload(obj, preloads) do
    maybe_do_preload(obj, preloads)
  end

  def maybe_do_preload(%Ecto.Association.NotLoaded{}, _), do: nil

  def maybe_do_preload(obj, preloads) when is_struct(obj) do
    @repo.preload(obj, preloads)
  rescue
    ArgumentError ->
      obj

    MatchError ->
      obj
  end

  def maybe_do_preload(obj, _), do: obj
end
