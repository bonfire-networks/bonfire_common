if Code.ensure_loaded?(Igniter.Mix.Task) do
defmodule Mix.Tasks.Bonfire.Gen.View do
  @moduledoc """
  `just mix bonfire.gen.view Bonfire.MyUIExtension MyView`

  will present you with a diff and create new files
  """
  import Bonfire.Common.Extend
  use_if_enabled Igniter.Mix.Task
     alias Bonfire.Common.Mix.Tasks.Helpers

  def igniter(igniter, [extension, module_name | _] = _argv) do
    # app_name = Bonfire.Application.name()

    ext_module =
      extension
      |> Macro.camelize()

    snake_name = Macro.underscore(extension)

    module_name =
      String.trim_trailing(ext_module <> "." <> module_name, "Live")
      |> Kernel.<>("Live")
      |> Igniter.Project.Module.parse()

    # |> IO.inspect()

    lib_path_prefix = "lib/web/views"

    igniter
    |> Igniter.create_new_file(
      Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix),
      """
      defmodule #{inspect(module_name)} do
        use Bonfire.UI.Common.Web, :surface_live_view

        declare_nav_link(l("#{ext_module} Home"), page: "#{snake_name}", icon: "ri:home-line", emoji: "🧩")

        on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

        def mount(_params, _session, socket) do
          {:ok,
          assign(
            socket,
            page: "#{snake_name}",
            page_title: "#{ext_module}"
          )}
        end

        def handle_event(
              "custom_event",
              _attrs,
              socket
            ) do
          # handle the event here
          {:noreply, socket}
        end
      end

      """
    )
    |> Igniter.create_new_file(
      Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix, "sface"),
      """
      <div>
        Hello, This is a new view for #{ext_module}.

        You can include a component by uncommenting the line below and updating it with your component module name and then passing the assigns you need:
        {!-- <#{ext_module}.AdvancedComponentLive name="#{ext_module}" /> --}
      </div>
      """
    )
  end
end
end