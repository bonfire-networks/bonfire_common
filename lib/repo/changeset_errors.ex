defmodule Bonfire.Repo.ChangesetErrors do

  def cs_to_string(%Ecto.Changeset{} = changeset) do
    IO.inspect(changeset)
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", do_to_string(value))
      end)
    end)
    |> many()
  end
  def cs_to_string(changeset), do: changeset

  defp many(changeset) do
    changeset
    |> Enum.reduce("", fn {k, v}, acc ->
      IO.inspect(v: v)
      joined_errors = do_to_string(v, "; ")

      "#{acc} #{k}: #{joined_errors}"
    end)
  end

  defp do_to_string(val, sep \\ ", ") when is_list(val) do
    Enum.map(val, &do_to_string/1)
    |> Enum.filter(& &1)
    |> Enum.join(sep)
  end
  defp do_to_string(empty, _) when empty == %{} or empty == "", do: nil
  defp do_to_string(%{} = many, _), do: many(many)
  defp do_to_string(val, _), do: to_string(val)
end
