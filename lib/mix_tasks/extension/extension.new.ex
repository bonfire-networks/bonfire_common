defmodule Mix.Tasks.Extension.New do
  use Mix.Task

  def run([extension_name]) do
    System.cmd(
      "git",
      [
        "clone",
        "https://github.com/bonfire-networks/bonfire_extension_template.git",
        extension_name
      ],
      cd: "extensions"
    )

    rename_modules(extension_name)
    rename_config_file(extension_name)
    remove_git(extension_name)
  end

  defp rename_modules(extension_name) do
    # Get all .ex, .exs, and .md files in the extension directory
    ["**/*.ex", "**/*.exs", "**/*.md"]
    |> Enum.flat_map(&Path.wildcard("extensions/#{extension_name}/" <> &1))
    |> Enum.each(fn path ->
      # Read the file
      file_content = File.read!(path)

      # Replace the module names
      new_content =
        String.replace(file_content, "bonfire_extension_template", "bonfire_#{extension_name}")

      new_content =
        String.replace(
          new_content,
          "Bonfire.ExtensionTemplate",
          "Bonfire.#{Macro.camelize(extension_name)}"
        )

      # Write the new content to the file
      File.write!(path, new_content)
    end)
  end

  defp rename_config_file(extension_name) do
    old_name = "extensions/#{extension_name}/config/bonfire_extension_template.exs"
    new_name = "extensions/#{extension_name}/config/bonfire_#{extension_name}.exs"
    File.rename(old_name, new_name)
  end

  defp remove_git(extension_name) do
    System.cmd("rm", ["-rf", ".git"], cd: "extensions/#{extension_name}")
  end
end
