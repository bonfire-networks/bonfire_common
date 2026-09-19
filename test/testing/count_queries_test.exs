defmodule Bonfire.Common.Testing.CountQueriesTest do
  @moduledoc """
  `count_queries/1` counts the queries a function made, so a test can pin work as batched.

  It counts the calling process only: telemetry handlers are global, so a LiveView or a `Task`
  querying at the same time would otherwise be counted and the assertion would be flaky rather
  than wrong, which is worse.
  """
  use Bonfire.Common.DataCase, async: false

  import Bonfire.Common.Testing, only: [count_queries: 1]

  alias Bonfire.Common.Repo
  alias Bonfire.Data.Identity.User

  defp one_query, do: Repo.aggregate(User, :count)

  test "counts one query as one" do
    assert {count, 1} = count_queries(fn -> one_query() end)
    assert is_integer(count)
  end

  test "counts a function that queries nothing as none" do
    assert {:nothing, 0} = count_queries(fn -> :nothing end)
  end

  test "counts each query, so an N+1 shows up as N" do
    assert {_, 3} = count_queries(fn -> Enum.map(1..3, fn _ -> one_query() end) end)
  end

  test "ignores queries another process made at the same time" do
    event = Bonfire.Common.Config.repo().config()[:telemetry_prefix] ++ [:query]

    {_, count} =
      count_queries(fn ->
        # emitted directly rather than by querying, so the other process needs no sandbox ownership
        Task.async(fn -> :telemetry.execute(event, %{total_time: 0}, %{}) end) |> Task.await()

        one_query()
      end)

    assert count == 1, "only the counted process's own query should be counted"
  end

  test "counts the queries even when the function raises" do
    # the handler must be detached either way, or every later count in this process is inflated
    assert_raise RuntimeError, fn ->
      count_queries(fn ->
        one_query()
        raise "boom"
      end)
    end

    assert {_, 1} = count_queries(fn -> one_query() end)
  end
end
