defmodule Bonfire.Repo.Delete do

  require Logger

  import Bonfire.Common.Config, only: [repo: 0]

  @spec soft_delete(any()) :: {:ok, any()} | {:error, :deletion_error}
  @doc "Just marks an entry as deleted in the database"
  def soft_delete(it), do: deletion_result(do_soft_delete(it))

  @spec soft_delete!(any()) :: any()
  @doc "Marks an entry as deleted in the database or throws an error"
  def soft_delete!(it), do: deletion_result!(do_soft_delete(it))

  defp do_soft_delete(it), do: repo().update(Bonfire.Repo.Changeset.soft_delete_changeset(it))

  @spec hard_delete(any()) :: {:ok, any()} | {:error, :deletion_error}
  @doc "Actually deletes an entry from the database"
  def hard_delete(it) do
    it
    |> repo().delete(
      stale_error_field: :id,
      stale_error_message: "has already been deleted"
    )
    |> deletion_result()
  end

  @spec hard_delete!(any()) :: any()
  @doc "Deletes an entry from the database, or throws an error"
  def hard_delete!(it),
    do: deletion_result!(hard_delete(it))

  # FIXME: boilerplate code, or should this be removed in favour of checking authorisation in contexts?
  def maybe_allow_delete?(user, context) do
    Map.get(Map.get(user, :local_user, %{}), :is_instance_admin) or
      maybe_creator_allow_delete?(user, context)
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{creator_id: creator_id})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{profile: %{creator_id: creator_id}})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{character: %{creator_id: creator_id}})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  # allow to delete self
  defp maybe_creator_allow_delete?(%{id: user_id}, %{id: id})
       when not is_nil(id) and not is_nil(user_id) do
    id == user_id
  end

  defp maybe_creator_allow_delete?(_, _), do: false

  def deletion_result({:error, e}) do
    if Code.ensure_loaded?(Bonfire.Fail.Error) do
      {:error, Bonfire.Fail.Error.error(:deletion_error, e)}
    else
      {:error, :deletion_error}
    end
  end
  def deletion_result(other), do: other

  def deletion_result!({:ok, val}), do: val
  def deletion_result!({:error, e}), do: throw(e)
  # defp deletion_result!(other), do: other

end
