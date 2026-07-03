defmodule Bonfire.Repo.Migrations.DropPointerTableIdIndex do
  @moduledoc false
  use Ecto.Migration
  use Needle.Migration.Indexable

  # Drops the legacy single-column pointers_pointer (table_id) index, superseded by
  # pointers_pointer_alive_type_id_idx (20260703000002 / init_pointers on fresh installs): same
  # leading column plus `id` ordering and the `deleted_at IS NULL` partial. On prod it served
  # ~0.003% of pointer index scans (110k vs 3.42B on the PK) while costing 644 MB + write
  # amplification; the covering index showed 280k+ scans within hours of creation.
  #
  # Like the other index migrations, run with `DB_STATEMENT_TIMEOUT=0 mise exec -- just db-migrate`:
  # DROP INDEX CONCURRENTLY waits for in-flight transactions and can exceed the 20s statement_timeout.
  def up do
    drop_index_for_pointer(Needle.Pointer.__schema__(:source), [:table_id])
  end

  def down do
    create_index_for_pointer(Needle.Pointer.__schema__(:source), [:table_id])
  end
end
