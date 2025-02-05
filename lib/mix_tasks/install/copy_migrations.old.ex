defmodule Mix.Tasks.Bonfire.Extension.CopyMigrations do
  use Mix.Task
  # import Macro, only: [camelize: 1, underscore: 1]
  # import Mix.Generator
  # import Mix.Ecto, except: [migrations_path: 1]

  # TODO: turn into an escript so it can be run without compiling the whole app?

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
    case OptionParser.parse(args, switches: @switches) do
      {opts, [], _} ->
        # None specified, will simply try copying any available extension.
        Mix.Tasks.Bonfire.Install.CopyMigrations.copy_all(
          nil,
          opts |> Keyword.put_new(:to, @default_path)
        )

      {opts, extensions, _} ->
        Mix.Tasks.Bonfire.Install.CopyMigrations.copy_for_extensions(
          nil,
          extensions,
          opts |> Keyword.put_new(:to, @default_path)
        )
    end

    # repo =
    #   List.first(parse_repo(args))
    #   |> IO.inspect(label: "repo")

    # if Mix.shell().yes?("Do you want to run these migrations on #{repo}?") do
    #   Mix.Task.run("ecto.migrate", [repo])
    # end
  end
end
