defmodule Bonfire.Common.Repo.Migrations.MaxUuidSortopForMax do
  @moduledoc false
  use Ecto.Migration

  # `max(uuid)` was created with the `<` operator as its `sortop`, copied from `min(uuid)`. Postgres uses `sortop` to answer `max(col)` from an index as `ORDER BY col USING sortop LIMIT 1`, so on a table big enough for the planner to choose that, `max` returned the MINIMUM (while a sequential scan returned the right answer). A max's `sortop` is `>`. The SQL is spelled out here rather than called from `Needle.ULID.Migration`, so this does not depend on which version of that fork is installed.
  defp create_max(sortop) do
    """
    create or replace aggregate max(uuid) (
      sfunc = max_uuid,
      stype = uuid,
      combinefunc = max_uuid,
      sortop = operator (#{sortop}),
      parallel = safe
    )
    """
  end

  def up, do: execute(create_max(">"))

  def down, do: execute(create_max("<"))
end
