defmodule Mix.Tasks.Bonfire.Gen.Extension do
  @moduledoc """
  `just mix bonfire.gen.extension Bonfire.MyExtension`

  will present you with a diff of new files to create your new extension and create a repo for it in `extensions/`
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      # description: "Creates a new Bonfire extension from a template",
      positional: [
        extension_name: [
          type: :string,
          required: true,
          doc: "Name of the extension to create"
        ]
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    [extension_name] = igniter.args.argv
    snake_name = Macro.underscore(extension_name)

    camel_name =
      extension_name
      |> String.replace("bonfire_", "bonfire/")
      |> Macro.camelize()

    igniter
    |> clone_template(snake_name)
    |> rename_modules(snake_name, camel_name)
    |> rename_config_file(snake_name)
    |> reset_git(snake_name)
    |> Igniter.add_notice(
      "Done! You can now start developing your extension in ./extensions/#{snake_name}/"
    )
  end

  defp clone_template(igniter, snake_name) do
    if File.exists?("extensions/bonfire_extension_template") do
      System.cmd("sh", [
        "-c",
        "cd extensions/bonfire_extension_template && find . -name '.git' -prune -o -print | cpio -pdm ../#{snake_name}"
      ])
    else
      System.cmd(
        "git",
        [
          "clone",
          "--depth",
          "1",
          "https://github.com/bonfire-networks/bonfire_extension_template.git",
          snake_name
        ],
        cd: "extensions"
      )
    end

    igniter
  end

  defp rename_modules(igniter, snake_name, camel_name) do
    patterns = ["**/*.ex", "**/*.exs", "**/*.md", "**/*.sface"]
    base_path = "extensions/#{snake_name}/"

    Enum.reduce(patterns, igniter, fn pattern, acc ->
      Path.wildcard(base_path <> pattern)
      |> Enum.reduce(acc, fn path, inner_acc ->
        inner_acc
        |> Igniter.include_existing_file(path)
        |> Igniter.update_file(path, fn source ->
          Rewrite.Source.update(source, :content, fn
            content when is_binary(content) ->
              content
              |> String.replace("bonfire_extension_template", snake_name)
              |> String.replace("Bonfire.ExtensionTemplate", camel_name)

            content ->
              content
          end)
        end)
      end)
    end)
  end

  defp rename_config_file(igniter, extension_name) do
    old_name = "extensions/#{extension_name}/config/bonfire_extension_template.exs"
    new_name = "extensions/#{extension_name}/config/#{extension_name}.exs"

    Igniter.move_file(igniter, old_name, new_name)
  end

  defp reset_git(igniter, extension_name) do
    cd_path = "extensions/#{extension_name}"

    System.cmd("rm", ["-rf", ".git"], cd: cd_path)
    System.cmd("git", ["init"], cd: cd_path)
    System.cmd("git", ["add", "."], cd: cd_path)
    System.cmd("git", ["commit", "-m", "new extension"], cd: cd_path)

    igniter
  end
end
