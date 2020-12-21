defmodule Bonfire.Common.Changesets do

  alias Ecto.Changeset

  def error(changeset, []), do: changeset
  def error(changeset, [{k, v} | errors]),
    do: error(Changeset.add_error(changeset, k, v), errors)

end
