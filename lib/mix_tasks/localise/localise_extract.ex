defmodule Mix.Tasks.Bonfire.Localise.Extract do
  use Mix.Task
  import Untangle
  @recursive true

  @shortdoc "Extracts translations from source code"

  @moduledoc """
  Extracts translations by recompiling the Elixir source code.

      mix gettext.extract [OPTIONS]

  Translations are extracted into POT (Portable Object Template) files (with a
  `.pot` extension). The location of these files is determined by the `:otp_app`
  and `:priv` options given by Gettext modules when they call `use Gettext`. One
  POT file is generated for each translation domain.

  It is possible to give the `--merge` option to perform merging
  for every Gettext backend updated during merge:

      mix gettext.extract --merge

  All other options passed to `gettext.extract` are forwarded to the
  `gettext.merge` task (`Mix.Tasks.Gettext.Merge`), which is called internally
  by this task. For example:

      mix gettext.extract --merge --no-fuzzy

  """

  @switches [merge: :boolean]

  def run(args) do
    Application.ensure_all_started(:gettext)
    _ = Mix.Project.get!()
    mix_config = Mix.Project.config()
    {opts, _} = OptionParser.parse!(args, switches: @switches)

    gettext_config =
      (mix_config[:gettext] || [])
      |> debug("gettext config")

    mix_config = Bonfire.Umbrella.MixProject.config()

    exts_to_localise =
      Bonfire.Mixer.deps_names_for(:localise, mix_config)
      |> debug("bonfire extensions to localise")

    deps_to_localise =
      Bonfire.Mixer.deps_names_for(:localise_self, mix_config)
      |> debug("other deps to localise")

    Mix.Tasks.Bonfire.Extension.Compile.touch_manifests()

    IO.puts(
      "First extract strings from all deps that use the Gettext module in bonfire_common..."
    )

    pot_files = extract(:bonfire_common, gettext_config, exts_to_localise)

    IO.puts("Next extract strings from deps with their own Gettext...")

    pot_files =
      Enum.reduce(deps_to_localise, pot_files, fn dep, pot_files ->
        pot_files ++ extract(String.to_atom(dep), gettext_config, dep)
      end)

    # pot_files |> debug("extracted pot_files")

    IO.puts("Save extracted strings...")

    for {path, contents} <- pot_files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      info("Extracted strings to #{Path.relative_to_cwd(path)}")
    end

    IO.puts("Merge saved strings...")

    if opts[:merge] do
      run_merge(pot_files, args)
    end

    :ok
  end

  defp extract(app, gettext_config, deps_to_localise) do
    Gettext.Extractor.enable()

    Mix.Tasks.Bonfire.Extension.Compile.force_compile(deps_to_localise)

    Gettext.Extractor.pot_files(
      app,
      gettext_config
    )
  after
    Gettext.Extractor.disable()
  end

  defp run_merge(pot_files, argv) do
    pot_files
    |> Enum.map(fn {path, _} -> Path.dirname(path) end)
    |> Enum.uniq()
    |> Task.async_stream(&Mix.Tasks.Gettext.Merge.run([&1 | argv]),
      ordered: false
    )
    |> Stream.run()
  end
end
