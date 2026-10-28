defmodule Bonfire.Common.Repo.MaxUuidAggregateTest do
  @moduledoc """
  `max(uuid)` is an aggregate of our own (`Needle.ULID.Migration`), which Postgres can answer from an index as `ORDER BY col USING sortop LIMIT 1` instead of reading every row. That shortcut uses the aggregate's `sortop`, so it has to be the `>` operator for a max: with `<` the index route returned the minimum, while a sequential scan returned the right answer, which made the thread feeds' "latest reply" wrong only on tables big enough for the planner to prefer the index (so in the full CI suite and on big instances, but not in a small test).

  Two ways to be on that route: turn sequential scans off on a small table, or give the planner a table big enough to choose it by itself, shaped like the thread feeds' lookup (`Bonfire.Social.Threads`, latest reply of a thread). Either way the plan is checked, so a test that stopped taking the route would fail rather than pass without testing anything.
  """
  use Bonfire.Common.DataCase, async: false
  @moduletag :backend

  alias Bonfire.Common.Repo

  @low "01a14b93-a43f-b495-7cc5-6f06090d375a"
  @high "01a17f13-3e75-3755-521d-d5b607ea0013"
  @other "01a17f13-3e75-3755-521d-d5b607ea0014"

  defp uuid(string), do: Ecto.UUID.dump!(string)

  defp explain(sql, params \\ []) do
    Repo.query!("EXPLAIN (COSTS OFF) " <> sql, params).rows |> List.flatten() |> Enum.join("\n")
  end

  describe "with sequential scans turned off" do
    setup do
      Repo.query!("CREATE TEMP TABLE max_uuid_test (grp int, id uuid PRIMARY KEY) ON COMMIT DROP")

      Repo.query!(
        "INSERT INTO max_uuid_test VALUES (1, $1), (1, $2), (2, $3)",
        [uuid(@low), uuid(@high), uuid(@other)]
      )

      Repo.query!("ANALYZE max_uuid_test")
      Repo.query!("SET LOCAL enable_seqscan = off")
      :ok
    end

    test "max over an index scan returns the larger id" do
      sql = "SELECT max(id) FROM max_uuid_test"

      assert explain(sql) =~ "Index Only Scan",
             "control: the plan has to be the index route this test is about"

      assert [[max]] = Repo.query!(sql).rows
      assert Ecto.UUID.load!(max) == @other
    end

    test "max over an index scan with a filter returns the larger id of what matches" do
      assert [[max]] = Repo.query!("SELECT max(id) FROM max_uuid_test WHERE grp = 1").rows
      assert Ecto.UUID.load!(max) == @high
    end

    test "max per group is right whichever way the planner reads it" do
      sql = "SELECT grp, max(id) FROM max_uuid_test GROUP BY grp ORDER BY grp"

      assert [[1, one], [2, two]] = Repo.query!(sql).rows
      assert {Ecto.UUID.load!(one), Ecto.UUID.load!(two)} == {@high, @other}
    end

    test "min over an index scan returns the smaller id" do
      assert [[min]] = Repo.query!("SELECT min(id) FROM max_uuid_test").rows
      assert Ecto.UUID.load!(min) == @low
    end
  end

  describe "on a table the planner reads from the index by itself" do
    # 60 threads of 500 replies each, ids rising with insertion order as ULIDs do. This is the shape of a thread's latest-reply lookup: `max(id)` of the rows in one thread, apart from the thread's own entry
    setup do
      Repo.query!(
        "CREATE TEMP TABLE replied_like (id uuid PRIMARY KEY, thread_id uuid) ON COMMIT DROP"
      )

      Repo.query!("CREATE INDEX replied_like_thread ON replied_like (thread_id)")

      Repo.query!("""
      INSERT INTO replied_like
      SELECT ('01a1' || lpad(to_hex(g), 28, '0'))::uuid, ('01a0' || lpad(to_hex(g % 60), 28, '0'))::uuid
      FROM generate_series(1, 30000) g
      """)

      Repo.query!("ANALYZE replied_like")
      :ok
    end

    test "a thread's latest reply is its newest, not its first" do
      sql =
        "SELECT max(id) FROM replied_like WHERE thread_id = ('01a0' || lpad(to_hex(7), 28, '0'))::uuid AND id != thread_id"

      assert explain(sql) =~ "Limit",
             "control: the planner has to take the index shortcut by itself, which is how the thread feeds got a wrong answer"

      assert [[max]] = Repo.query!(sql).rows
      # the last g with g % 60 = 7 below 30000 is 29947 (0x74fb)
      assert Ecto.UUID.load!(max) == "01a10000-0000-0000-0000-0000000074fb"
    end
  end
end
