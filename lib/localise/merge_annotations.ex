defmodule Mix.Tasks.Bonfire.Localise.MergeAnnotations do
  @shortdoc "Merges the annotated .po files written by several test runs"

  @moduledoc """
  Merges the annotated copies of each `.po` file from several directories into one directory:

      mix bonfire.localise.merge_annotations --into priv/localisation annotated-1 annotated-2

  CI spreads the test suite over several jobs, and each one annotates only the strings its own tests rendered (see `Bonfire.Common.Localise.POAnnotator`). This combines their URL comments per entry, so translators get the pages from every job. Files with the same name in the given directories are merged; the result is written under the same name into `--into`.
  """
  use Mix.Task

  alias Bonfire.Common.Localise.POAnnotator

  @impl true
  def run(args) do
    {opts, dirs} = OptionParser.parse!(args, strict: [into: :string])
    into = opts[:into] || Mix.raise("Pass the directory to write to, with --into")

    File.mkdir_p!(into)

    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.po")))
    |> Enum.group_by(&Path.basename/1)
    |> Enum.each(fn {name, paths} ->
      merged =
        paths
        |> Enum.map(&Expo.PO.parse_file!/1)
        |> POAnnotator.merge_annotations()

      File.write!(Path.join(into, name), Expo.PO.compose(merged))
      Mix.shell().info("Merged #{length(paths)} copies of #{name}")
    end)

    :ok
  end
end
