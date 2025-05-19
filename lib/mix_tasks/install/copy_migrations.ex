if Code.ensure_loaded?(Igniter.Mix.Task), do:
defmodule Mix.Tasks.Bonfire.Install.CopyMigrations do
  import Bonfire.Common.Extend
  use_if_enabled Igniter.Mix.Task
     alias Bonfire.Common.Mix.Tasks.Helpers

  @shortdoc "Copies migrations for the extension into the parent app"
  @doc """
  Usage:
  `just mix bonfire.install.copy_migrations my_extension`
  or
  `just mix bonfire.install.copy_migrations` 

  NOTE: if you don't specify what extension(s) to include, it will automatically include all extensions which:
  - start with `bonfire_`
  - and are included in the top-level app (not dependencies of dependencies)

  Optional args:

  --force (to not ask for confirmation before copying, or to overwrite existing migration files - only applies when not using Igniter)
  --from priv/repo/migrations (to change the source repo paths, relative to each extension path)
  --to repo/ (to change the target repo path (defaults to current flavour's migrations) relative to working directory)
  """

  @switches [from: :string, to: :string, force: :boolean]
  @default_repo_path "priv/repo"
  @default_mig_path @default_repo_path <> "/migrations"

  def igniter(igniter, args) do
    IO.inspect(args, label: "Args")

    case OptionParser.parse(args, switches: @switches) do
      {opts, [], _} ->
        # None specified, will simply try copying any available extension.
        copy_all(igniter, opts)

      {opts, extensions, _} ->
        copy_for_extensions(igniter, extensions, opts)
    end
  end

  def copy_all(igniter, opts) do
    extensions = Helpers.list_extensions()

    copy_for_extensions(igniter, extensions, opts)
  end

  def copy_for_extensions(igniter, extensions, opts) do
    IO.inspect(opts, label: "Options")

    to = opts[:to] || @default_repo_path

    dest_path =
      Path.expand(to, File.cwd!())
      |> IO.inspect(label: "to path")

    from = opts[:from] || @default_mig_path

    extension_paths =
      extensions
      |> IO.inspect(label: "deps to include")
      |> Bonfire.Mixer.dep_paths(from)
      |> IO.inspect(label: "paths to copy")

    if igniter do
      Igniter.include_glob(igniter, Path.join(dest_path, "**/*.{exs}"))
      |> Helpers.igniter_copy(extension_paths, dest_path, opts)
    else
      simple_copy(extension_paths, dest_path, opts)
    end
  end

  def simple_copy(extension_paths, dest_path, opts) when is_list(extension_paths),
    do: Enum.each(extension_paths, &simple_copy(&1, dest_path, opts))

  def simple_copy(source_path, dest_path, opts) do
    source_path
    |> IO.inspect()

    if opts[:force] do
      IO.puts(
        "\nCopying the following migrations from #{source_path} to #{dest_path}: \n#{inspect(File.ls!(source_path))}\n"
      )

      with {:error, reason, file} <- File.cp_r(source_path, dest_path) do
        IO.puts("\nERROR: Could not copy #{file} : #{inspect(reason)}\n")
      end
    else
      if IO.gets(
           "Will copy the following migrations from #{source_path} to #{dest_path}: \n#{inspect(File.ls!(source_path))}\n\nType y to confirm: "
         ) == "y\n" do
        File.cp_r(source_path, dest_path,
          on_conflict: fn source, destination ->
            IO.gets("Overwriting #{destination} by #{source}. Type y to confirm. ") == "y\n"
          end
        )
      end
    end
  end
end
