defmodule Mix.Tasks.Bonfire.Gen.Widget do
  @moduledoc """
  `just mix bonfire.gen.widget Bonfire.MyUIExtension MyWidget`

  will present you with a diff and create new files
  """
  use Igniter.Mix.Task
  alias Bonfire.Common.Mix.Tasks.Helpers

  def igniter(igniter, [extension, module_name | _] = _argv) do
    # app_name = Bonfire.Application.name()

    module_name =
      (Macro.camelize(extension) <> "." <> String.trim_trailing(module_name, "Live"))
      |> Kernel.<>("Live")
      |> Igniter.Project.Module.parse()

    # |> IO.inspect()

    lib_path_prefix = "lib/web/widgets"

    igniter
    |> Igniter.create_new_file(
      Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix),
      """
      defmodule #{inspect(module_name)} do
        use Bonfire.UI.Common.Web, :stateless_component

        prop widget_title, :string, default: nil
        prop class, :css_class, default: nil

        # to add extra props or slots, see https://surface-ui.org/properties and https://surface-ui.org/slots
      end
      """
    )
    |> Igniter.create_new_file(
      Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix, "sface"),
      """
      <Bonfire.UI.Common.WidgetBlockLive widget_title={e(@widget_title, "")} class={@class, ""}>
        Hello world!
      </Bonfire.UI.Common.WidgetBlockLive>
      """
    )
  end
end
