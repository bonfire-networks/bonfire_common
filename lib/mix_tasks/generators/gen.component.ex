if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.Bonfire.Gen.Component do
    @moduledoc """
    `just mix bonfire.gen.component stateless Bonfire.MyUIExtension MyComponent`
    or
    `just mix bonfire.gen.component stateful Bonfire.MyUIExtension MyComponent`

    will present you with a diff and create new files
    """

    import Bonfire.Common.Extend
    use_if_enabled(Igniter.Mix.Task)
    alias Bonfire.Common.Mix.Tasks.Helpers

    def igniter(igniter, [state, extension, module_name | _] = _argv) do
      gen_component(igniter, extension, module_name, state)
    end

    def gen_component(igniter, extension, module_name, state)
        when state in ["stateful", "stateless"] do
      ext_module =
        extension
        |> Macro.camelize()

      snake_name = Macro.underscore(extension)

      module_name =
        String.trim_trailing(ext_module <> "." <> module_name, "Live")
        |> Kernel.<>("Live")
        |> Igniter.Project.Module.parse()

      # |> IO.inspect()

      lib_path_prefix = "lib/web/components"

      igniter
      |> Igniter.create_new_file(
        Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix),
        """
        defmodule #{inspect(module_name)} do
          use Bonfire.UI.Common.Web, :#{state}_component

          prop name, :string, default: nil
        end
        """
      )
      |> Igniter.create_new_file(
        Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix, "sface"),
        """
        <div>
          Hello, This is a new #{state} component for #{ext_module}.

          You can include a other components by uncommenting the line below and updating it with your other component module name and then passing the assigns you need:
          {!-- <#{ext_module}.SimpleComponentLive name="#{ext_module}" /> --}
        </div>
        """
      )
    end
  end
end
