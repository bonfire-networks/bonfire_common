defmodule Bonfire.Common.DataMigrationRunnerTest do
  @moduledoc """
  A data migration works through its rows in batches, often in the background over an instance's whole history, so one batch that fails must not end the run: an async data migration is marked done when it starts and never re-run, so whatever came after a failing batch was left unmigrated for good (bonfire.cafe, 18 October: 2507 old group mirrors never repaired).
  """
  use Bonfire.Common.DataCase, async: false

  @moduletag :backend

  defmodule RaisingMigration do
    @moduledoc false
    import Ecto.Query
    use EctoSparkles.DataMigration

    @impl EctoSparkles.DataMigration
    def base_query(opts) do
      from(p in Needle.Pointer, where: p.id in ^opts[:ids], select: %{id: p.id})
    end

    @impl EctoSparkles.DataMigration
    def config do
      %EctoSparkles.DataMigration.Config{
        async: false,
        batch_size: 1,
        throttle_ms: 0,
        repo: Bonfire.Common.Repo,
        first_id: "00000000000000000000000000"
      }
    end

    @impl EctoSparkles.DataMigration
    def migrate(results, opts) do
      Enum.each(results, fn %{id: id} ->
        if id == opts[:raise_on], do: raise("a row this migration can't handle")
        send(opts[:test_pid], {:migrated, id})
      end)
    end
  end

  defp pointer! do
    Bonfire.Common.Repo.insert!(%Needle.Pointer{
      id: Needle.UID.generate(),
      table_id: Needle.Util.table_id(Bonfire.Data.Social.Post)
    })
  end

  test "a data migration goes on to the next batch after one that raises" do
    # ids are ordered, so `first` is the first batch
    [first, second] = [pointer!(), pointer!()] |> Enum.map(& &1.id) |> Enum.sort()

    EctoSparkles.DataMigration.Runner.run(RaisingMigration,
      ids: [first, second],
      raise_on: first,
      test_pid: self()
    )

    assert_received {:migrated, ^second},
                    "the batch after the one that raised was never migrated"
  end
end
