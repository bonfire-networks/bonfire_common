defmodule Needle.Repo.Migrations.FixPointersTriggerFunction do
  @moduledoc false
  use Ecto.Migration

  # Re-creates the trigger function that deletes a pointable's row when its pointer is deleted or soft-deleted, since it built its query with `|` instead of `||` and so failed with "operator does not exist: text | uuid" whenever it fired.
  def up, do: Needle.Migration.create_pointers_trigger_function()
  def down, do: nil
end
