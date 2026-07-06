defmodule Bonfire.Repo.Migrations.CreatePgStatStatementsExtension do
  @moduledoc """
  Enables the `pg_stat_statements` extension where possible — the DB-side ground truth used by ops tooling (`Bonfire.Common.Telemetry.StormRecorder`'s window diff, the perf plans' attribution snippets).

  NON-FATAL by design: migrations run at boot, and on managed databases the app user may lack the privilege (or the library may not be in `shared_preload_libraries`, in which case the extension's views exist but error on read — harmless, callers probe first). A failure here must never block boot, so privilege errors are swallowed with a NOTICE.
  """
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'pg_stat_statements not enabled (insufficient privilege), ops tooling will report it as unavailable';
      WHEN undefined_file THEN
        RAISE NOTICE 'pg_stat_statements not enabled (library not installed on this server)';
    END
    $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      DROP EXTENSION IF EXISTS pg_stat_statements;
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'could not drop pg_stat_statements (insufficient privilege)';
    END
    $$;
    """)
  end
end