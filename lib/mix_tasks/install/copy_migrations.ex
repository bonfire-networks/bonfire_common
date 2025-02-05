defmodule Mix.Tasks.Bonfire.Install.CopyMigrations do
  use Igniter.Mix.Task
  alias Bonfire.Common.Mix.Tasks.Helpers
  # import Macro, only: [camelize: 1, underscore: 1]
  # import Mix.Generator
  # import Mix.Ecto, except: [migrations_path: 1]

  # TODO: turn into an escript so it can be run without compiling the whole app

  @shortdoc "Generates migrations for the extension"
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
  --to priv/repo/ (to change the target repo path (defaults to current flavour's migrations) relative to working directory)
  """

  @switches [from: :string, to: :string, force: :boolean]
  @default_repo_path "repo"
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
    extensions_pattern =
      Bonfire.Common.Utils.maybe_apply(Bonfire.Mixer, :multirepo_prefixes, [],
        fallback_return: []
      ) ++ ["bonfire"] ++ Bonfire.Common.Config.get([:extensions_pattern], [])

    extensions =
      (Bonfire.Common.Utils.maybe_apply(Bonfire.Mixer, :deps_tree_flat, [], fallback_return: nil) ||
         Bonfire.Common.Extensions.loaded_deps_names())
      |> IO.inspect(label: "all deps")
      |> Enum.map(&to_string/1)
      |> Enum.filter(fn
        #  FIXME: make this configurable
        "bonfire_" <> _ -> true
        name -> String.starts_with?(name, extensions_pattern)
      end)

    copy_for_extensions(igniter, extensions, opts)
  end

  def copy_for_extensions(igniter, extensions, opts) do
    IO.inspect(opts, label: "Options")

    path = opts[:to] || Path.expand(@default_repo_path, Bonfire.Mixer.flavour_path())

    dest_path =
      Path.expand(path, File.cwd!())
      |> IO.inspect(label: "to path")

    extension_paths =
      extensions
      |> IO.inspect(label: "deps to include")
      |> Bonfire.Mixer.dep_paths(opts[:from] || "priv/" <> @default_mig_path)
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
