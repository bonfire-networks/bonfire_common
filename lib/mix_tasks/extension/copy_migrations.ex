defmodule Mix.Tasks.Bonfire.Extension.CopyMigrations do
  use Mix.Task
  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator
  import Mix.Ecto, except: [migrations_path: 1]

  # TODO: turn into an escript so it can be run without compiling the whole app

  @shortdoc "Generates migrations for the extension"
  @doc """
  Usage:
  `just mix bonfire.extension.copy_migrations my_extension`
  or
  `just mix bonfire.extension.copy_migrations` 

  NOTE: if you don't specify what extension(s) to include, it will automatically include all extensions which:
  - start with `bonfire_`
  - and are included in the top-level app (not dependencies of dependencies)

  Optional args:

  --force (to not ask for confirmation before copying, or to overwrite existing migration files)
  --from priv/repo/migrations (to change the source repo paths, relative to each extension path)
  --to priv/repo/migrations (to change the target repo path (defaults to current flavour's migrations) relative to working directory)
  --repo MyRepo (to specify what repo to migrate after)
  """

  @switches [from: :string, to: :string, force: :boolean]
  @default_repo_path "repo/migrations"
  @default_path "priv/" <> @default_repo_path

  def run(args) do
    IO.inspect(args)

    repo =
      List.first(parse_repo(args))
      |> IO.inspect()

    case OptionParser.parse(args, switches: @switches) do
      {opts, [], _} ->
        # None specified, will simply try copying any available extension.
        maybe_copy(opts)

      {opts, extensions, _} ->
        extensions
        |> maybe_copy(opts)
    end

    # if Mix.shell().yes?("Do you want to run these migrations on #{repo}?") do
    #   Mix.Task.run("ecto.migrate", [repo])
    # end
  end

  def maybe_copy(extensions \\ nil, opts) do
    opts
    |> IO.inspect()

    path = opts[:to] || Path.expand(@default_repo_path, Bonfire.Mixer.flavour_path())

    dest_path =
      Path.expand(path, File.cwd!())
      |> IO.inspect()

    (extensions ||
       Bonfire.Mixer.deps_names_for(:bonfire)
       |> Enum.reject(fn
         "bonfire_" <> _ -> false
         _ -> true
       end))
    |> Bonfire.Mixer.dep_paths(opts[:from] || @default_path)
    |> copy(dest_path, opts)
  end

  def copy(extension_paths, dest_path, opts) when is_list(extension_paths),
    do: Enum.each(extension_paths, &copy(&1, dest_path, opts))

  def copy(source_path, dest_path, opts) do
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
