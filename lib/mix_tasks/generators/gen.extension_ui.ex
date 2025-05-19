if Code.ensure_loaded?(Igniter.Mix.Task) do
defmodule Mix.Tasks.Bonfire.Gen.Extension.Ui do
  @moduledoc """
  `just mix bonfire.gen.extension.ui Bonfire.MyExtension`

  will present you with a diff of new files to create your new extension and create a repo for it in `extensions/`
  """

  import Bonfire.Common.Extend
  use_if_enabled Igniter.Mix.Task
   
  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      # description: "Creates a new Bonfire extension from a template",
      positional: [
        extension_name: [
          type: :string,
          required: true,
          doc: "Name of the UI extension to create"
        ]
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    [extension_name] = igniter.args.argv
    # snake_name = Macro.underscore(extension_name)

    camel_name =
      extension_name
      |> String.replace("bonfire_", "bonfire/")
      |> Macro.camelize()

    igniter
    |> Igniter.compose_task(Mix.Tasks.Bonfire.Gen.Extension, [camel_name])
    |> Igniter.compose_task(Mix.Tasks.Bonfire.Gen.Ui, [camel_name])
  end
end
end