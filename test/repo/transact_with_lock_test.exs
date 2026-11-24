defmodule Bonfire.Common.Repo.TransactWithLockTest do
  @moduledoc """
  `transact_with_lock/3` runs a fun in a transaction holding a lock on a key, so two callers with the same key (eg. two jobs finding or making the same record) take turns, while callers with other keys don't wait.

  The test sandbox shares one connection between processes, on which a lock never blocks, so each caller here runs on a connection of its own, outside the sandbox. They only take locks and write nothing.
  """
  use ExUnit.Case, async: false

  alias Bonfire.Common.Repo

  # runs `fun` on a connection of its own, holding the lock on `key`, telling the test when it has the lock, and waiting for `:release` before letting go
  defp holder(test, name, key) do
    Task.async(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.transact_with_lock(key, fn ->
          send(test, {:locked, name})

          receive do
            {:release, ^name} -> {:ok, name}
          after
            5_000 -> {:error, :never_released}
          end
        end)
      end)
    end)
  end

  test "a second caller with the same key waits until the first lets go" do
    key = {:upload, System.unique_integer([:positive])}

    first = holder(self(), :first, key)
    assert_receive {:locked, :first}, 5_000

    second = holder(self(), :second, key)
    refute_receive {:locked, :second}, 500

    send(first.pid, {:release, :first})
    assert {:ok, :first} = Task.await(first)

    assert_receive {:locked, :second}, 5_000
    send(second.pid, {:release, :second})
    assert {:ok, :second} = Task.await(second)
  end

  test "a caller with another key doesn't wait" do
    first = holder(self(), :first, {:upload, System.unique_integer([:positive])})
    assert_receive {:locked, :first}, 5_000

    other = holder(self(), :other, {:upload, System.unique_integer([:positive])})
    assert_receive {:locked, :other}, 5_000

    send(other.pid, {:release, :other})
    send(first.pid, {:release, :first})
    assert {:ok, :other} = Task.await(other)
    assert {:ok, :first} = Task.await(first)
  end

  test "it answers as `transact_with/2` does" do
    assert {:ok, :done} =
             Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
               Repo.transact_with_lock(:any_key, fn -> {:ok, :done} end)
             end)
  end
end
