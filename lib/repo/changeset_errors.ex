defmodule Bonfire.Repo.ChangesetErrors do

  def cs_to_string(%Ecto.Changeset{} = changeset) do
    IO.inspect(changeset)
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", do_to_string(value))
      end)
    end)
    |> Enum.reduce("", fn {k, v}, acc ->
      joined_errors = Enum.join(v, "; ")
      "#{acc} #{k}: #{joined_errors}"
    end)
  end
  def cs_to_string(changeset), do: changeset

  defp do_to_string(val) when is_list(val) do
    Enum.join(val, ",")
  end
  defp do_to_string(val), do: to_string(val)
end
