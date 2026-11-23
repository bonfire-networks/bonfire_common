defmodule Bonfire.Common.Import.Zip do
  @moduledoc """
  Reading an uploaded zip for an import source (see `Bonfire.Common.ImportModule`), safely: the zip comes from the person uploading it, so every entry name is checked, and the whole sized, before anything is read, and only the entries a source asks for are ever read or extracted.

  The limits are `max_archive_entries` and `max_archive_size` in `Bonfire.Common.Import`'s config, which the runtime config sets from `IMPORT_ARCHIVE_MAX_ENTRIES` and `IMPORT_ARCHIVE_LIMIT`.
  """
  use Bonfire.Common.Config
  use Bonfire.Common.Localise
  import Untangle

  @doc "The files in the zip at `zip_path`, as `{name, uncompressed size}`, leaving out directories (only prefixes of the names under them)."
  def table(zip_path) do
    case :zip.table(String.to_charlist(zip_path)) do
      {:ok, table} ->
        entries =
          for {:zip_file, name, info, _comment, _offset, _comp_size} <- table,
              not String.ends_with?(to_string(name), "/"),
              do: {to_string(name), elem(info, 1)}

        {:ok, entries}

      _ ->
        {:error, l("This is not a zip archive")}
    end
  end

  @doc "Checks the entries of `table/1` before anything is read: every name must stay inside a folder once extracted, no name may appear twice, and the whole must fit the limits."
  def check_entries(entries) do
    names = Enum.map(entries, &elem(&1, 0))

    cond do
      Enum.any?(names, &(Path.safe_relative(&1) == :error)) ->
        {:error, l("This archive has a file that would be written outside its folder")}

      length(names) != length(Enum.uniq(names)) ->
        {:error, l("This archive has the same file twice")}

      # defaults as in the runtime config
      length(names) > (Config.get([Bonfire.Common.Import, :max_archive_entries]) || 100_000) ->
        {:error, l("This archive has too many files")}

      Enum.sum(Enum.map(entries, &elem(&1, 1))) >
          (Config.get([Bonfire.Common.Import, :max_archive_size]) || 5_000_000_000) ->
        {:error, l("This archive is too big")}

      true ->
        :ok
    end
  end

  @doc "Reads `names` (relative to the folder `root` inside the zip) into memory, returned by those relative names."
  def read_entries(_zip, _root, []), do: {:ok, %{}}

  def read_entries(zip, root, names) do
    case :zip.extract(String.to_charlist(zip), [
           :memory,
           {:file_list, Enum.map(names, &String.to_charlist(root <> &1))}
         ]) do
      {:ok, files} ->
        {:ok,
         Map.new(files, fn {name, data} ->
           {String.replace_prefix(to_string(name), root, ""), data}
         end)}

      e ->
        error(e, l("Could not read this archive"))
    end
  end

  @doc "Extracts `names` (relative to the folder `root` inside the zip) into `dir` as the zip has them, and returns the folder where they're found by their relative names. Only regular files are kept, so a link inside the zip can't point the importer at another file on our disk."
  def extract(_zip, _dir, _root, []), do: {:ok, nil}

  def extract(zip, dir, root, names) do
    with {:ok, paths} <-
           :zip.extract(String.to_charlist(zip), [
             {:file_list, Enum.map(names, &String.to_charlist(root <> &1))},
             {:cwd, String.to_charlist(dir)}
           ]) do
      for path <- paths, path = to_string(path) do
        case File.lstat(path) do
          {:ok, %{type: :regular}} -> :ok
          _ -> File.rm_rf(path)
        end
      end

      {:ok, Path.join(dir, root)}
    else
      e -> error(e, l("Could not extract the archive's files"))
    end
  end
end
