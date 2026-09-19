defmodule Bonfire.Common.Repo.TransactWithTest do
  @moduledoc """
  `transact_with/2` maps a fun's return onto a transaction, and never leaves writes behind.

  An ok tuple commits, an error tuple rolls back and is returned, and a `Postgrex.Error` raised inside the fun rolls back and comes back as an error tuple too, since that is what this function's contract promises. The exception is when it runs nested inside someone else's transaction: Postgres has aborted that one, so the error is re-raised to unwind it rather than handed back to a caller who would keep querying a dead transaction.

  A statement-level write (`insert_all/3`) is how the raised path is reached in practice, since Ecto can only turn a constraint violation into `Ecto.ConstraintError` when there is a changeset constraint to match it against.
  """
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.Repo
  alias Bonfire.Data.Identity.Caretaker

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    other = Bonfire.Me.Fake.fake_user!(account)
    {:ok, user: user, other: other}
  end

  defp put_caretaker(id, caretaker_id) do
    Repo.insert_all(Caretaker, [%{id: id, caretaker_id: caretaker_id}], on_conflict: :nothing)
  end

  defp caretaker_id_of(id) do
    case Repo.get(Caretaker, id) do
      %Caretaker{caretaker_id: caretaker_id} -> caretaker_id
      _ -> nil
    end
  end

  test "an ok tuple commits and its value is returned", %{user: user, other: other} do
    assert {:ok, :done} =
             Repo.transact_with(fn ->
               put_caretaker(user.id, other.id)
               {:ok, :done}
             end)

    assert caretaker_id_of(user.id) == other.id
  end

  test "an error tuple rolls the writes back and is returned", %{user: user, other: other} do
    assert {:error, :nope} =
             Repo.transact_with(fn ->
               put_caretaker(user.id, other.id)
               {:error, :nope}
             end)

    refute caretaker_id_of(user.id)
  end

  test "a Postgrex.Error comes back as an error tuple, with the writes rolled back", %{user: user} do
    # an id with nothing behind it, so the row's pointer FK cannot resolve
    bogus = Needle.UID.generate()

    assert {:error, _} =
             Repo.transact_with(fn ->
               put_caretaker(user.id, user.id)
               put_caretaker(bogus, bogus)
               {:ok, :unreachable}
             end)

    refute caretaker_id_of(user.id)
  end

  test "nested in another transaction it re-raises instead, to unwind the aborted one", %{
    user: user
  } do
    bogus = Needle.UID.generate()

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn ->
        Repo.transact_with(fn ->
          put_caretaker(user.id, user.id)
          put_caretaker(bogus, bogus)
          {:ok, :unreachable}
        end)
      end)
    end

    refute caretaker_id_of(user.id)
  end
end
