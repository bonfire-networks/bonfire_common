defmodule Bonfire.Common.MigratorTest do
  @moduledoc """
  Running migrations one by one at boot (`EctoSparkles.Migrator.run_pending/3`).

  A production connection carries a Postgres `statement_timeout`, and a migration that rewrites a big table outlasts it, so migrations get connections without it. And a migration that fails anyway goes to `migration_error_callback_fn`, and the run carries on.

  These run outside the SQL sandbox, since migrations hold connections of their own, and remove the `schema_migrations` rows they add.
  """
  use ExUnit.Case, async: false
  @moduletag :backend

  alias Bonfire.Common.Repo
  alias EctoSparkles.Migrator

  # far in the past, so they can't collide with a real migration
  @slow 19_700_101_000_001
  @failing 19_700_101_000_002
  @fine 19_700_101_000_003

  defmodule SlowMigration do
    use Ecto.Migration
    def up, do: execute("SELECT pg_sleep(1.5)")
    def down, do: :ok
  end

  defmodule FailingMigration do
    use Ecto.Migration
    def up, do: execute("SELECT 1/0")
    def down, do: :ok
  end

  defmodule FineMigration do
    use Ecto.Migration
    def up, do: execute("SELECT 1")
    def down, do: :ok
  end

  # a pool of real connections, which the sandboxed test repo doesn't give, with whatever parameters a test needs
  defp start_repo(parameters) do
    {:ok, pid} =
      Repo.start_link(
        name: nil,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: parameters
      )

    pid
  end

  setup do
    on_exit(fn ->
      pid = start_repo([])
      Repo.put_dynamic_repo(pid)

      Repo.query!("DELETE FROM schema_migrations WHERE version = ANY($1)", [
        [@slow, @failing, @fine]
      ])

      Supervisor.stop(pid)
    end)

    :ok
  end

  # what a failure is reported to, as `migration_error_callback_fn`
  def report(version, desc, error, _stacktrace) do
    send(:persistent_term.get({__MODULE__, :test_pid}), {:migration_failed, version, desc, error})
  end

  test "a migration slower than the connection's statement timeout still runs" do
    limited = start_repo(statement_timeout: "1000")
    Repo.put_dynamic_repo(limited)

    # the positive first: on such a connection the same statement is cancelled
    assert_raise Postgrex.Error, ~r/statement timeout/, fn ->
      Repo.query!("SELECT pg_sleep(1.5)")
    end

    assert [{:ok, @slow, "slow"}] =
             Migrator.run_pending(Repo, &report/4, [{@slow, "slow", SlowMigration}])
  after
    Repo.put_dynamic_repo(Repo)
  end

  test "a failed migration goes to `migration_error_callback_fn`, and the next one still runs" do
    :persistent_term.put({__MODULE__, :test_pid}, self())
    Repo.put_dynamic_repo(start_repo([]))

    assert [{:error, @failing, "failing", _}, {:ok, @fine, "fine"}] =
             Migrator.run_pending(Repo, &report/4, [
               {@failing, "failing", FailingMigration},
               {@fine, "fine", FineMigration}
             ])

    assert_received {:migration_failed, @failing, "failing", %Postgrex.Error{}}
  after
    Repo.put_dynamic_repo(Repo)
  end
end
