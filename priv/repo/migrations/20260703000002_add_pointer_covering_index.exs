defmodule Bonfire.Repo.Migrations.AddPointerCoveringIndex do
  @moduledoc false
  use Ecto.Migration
  use Needle.Migration.Indexable

  def up do
    Needle.Migration.add_pointer_covering_index()
  end

  def down do
    Needle.Migration.drop_pointer_covering_index()
  end
end
