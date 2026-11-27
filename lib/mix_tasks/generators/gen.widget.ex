if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.Bonfire.Gen.Widget do
    @moduledoc """
    `just mix bonfire.gen.widget Bonfire.MyUIExtension MyWidget`

    will present you with a diff and create new files
    """
    import Bonfire.Common.Extend
    use_if_enabled(Igniter.Mix.Task)
    alias Bonfire.Common.Mix.Tasks.Helpers

    def igniter(igniter) do
      igniter_with_argv(igniter, igniter.args.argv)
    end

    def igniter_with_argv(igniter, [extension, module_name | _] = _argv) do
      # app_name = Bonfire.Application.name()

      module_name =
        (Macro.camelize(extension) <> "." <> String.trim_trailing(module_name, "Live"))
        |> Kernel.<>("Live")
        |> Igniter.Project.Module.parse()

      IO.puts("Adding UI widget #{module_name}...")

      # the name shown where widgets are picked, eg. `MyWidgetLive` gives "My widget"
      widget_name =
        module_name
        |> Module.split()
        |> List.last()
        |> String.replace_suffix("Live", "")
        |> Macro.underscore()
        |> String.replace("_", " ")
        |> String.capitalize()

      lib_path_prefix = "lib/web/widgets"

      igniter
      |> Igniter.create_new_file(
        Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix),
        """
        defmodule #{inspect(module_name)} do
          use Bonfire.UI.Common.Web, :stateless_component

          # registers it so it can be placed (options: id, width, props, skeleton, current_user_required)
          declare_widget(l(#{inspect(widget_name)}))

          prop widget_title, :string, default: nil

          # to add extra props or slots, see https://surface-ui.org/properties and https://surface-ui.org/slots
        end
        """
      )
      |> Igniter.create_new_file(
        Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix, "sface"),
        """
        {!-- WidgetBlockLive and the place give frame, header and spacing; build the body from the widget-* primitives in app.css --}
        <Bonfire.UI.Common.WidgetBlockLive widget_title={@widget_title || l(#{inspect(widget_name)})}>
          <div data-role="widget-body">
            Hello world!
          </div>
        </Bonfire.UI.Common.WidgetBlockLive>
        """
      )
    end
  end
end
