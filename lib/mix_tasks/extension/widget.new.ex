defmodule Mix.Tasks.Bonfire.Widget.New do
  @moduledoc """
  `just mix bonfire.widget.new Bonfire.MyUIExtension.MyWidget`

  will present you with a diff and create new files
  """
  import Bonfire.Common.Extend
  use_if_enabled Igniter.Mix.Task

  def igniter(igniter, [module_name | _] = argv) do
    app_name = Bonfire.Application.name()

    module_name =
      String.trim_trailing(module_name, "Live")
      |> Kernel.<>("Live")
      |> Igniter.Code.Module.parse()

    # |> IO.inspect()

    path_prefix = "lib/web/widgets"

    igniter
    |> Igniter.create_new_elixir_file(ext_path_for_module(module_name, path_prefix), """
    defmodule #{inspect(module_name)} do
      use Bonfire.UI.Common.Web, :stateless_component

      prop widget_title, :string, default: nil
      prop class, :css_class, default: nil

      # to add extra props or slots, see https://surface-ui.org/properties and https://surface-ui.org/slots
    end
    """)
    |> Igniter.create_new_file(ext_path_for_module(module_name, path_prefix, "sface"), """
    <Bonfire.UI.Common.WidgetBlockLive widget_title={e(@widget_title, "")} class={@class, ""}>
      Hello world!
    </Bonfire.UI.Common.WidgetBlockLive>
    """)
  end

  def ext_path_for_module(
        module_name,
        kind_or_prefix \\ "lib",
        file_ext \\ nil,
        path_prefix \\ "extensions"
      ) do
    path =
      case module_name
           |> Module.split()
           |> IO.inspect() do
        ["Bonfire", ext | rest] -> ["Bonfire#{ext}"] ++ rest
        other -> other
      end
      |> Enum.map(&Macro.underscore/1)

    first = List.first(path)
    last = List.last(path)
    leading = path |> Enum.drop(1) |> Enum.drop(-1)

    first_prefix = [path_prefix, first]

    case kind_or_prefix do
      :test ->
        if String.ends_with?(last, "_test") do
          Path.join(first_prefix ++ ["test" | leading] ++ ["#{last}.#{file_ext || "exs"}"])
        else
          Path.join(first_prefix ++ ["test" | leading] ++ ["#{last}_test.#{file_ext || "exs"}"])
        end

      "test/support" ->
        case leading do
          [] ->
            Path.join(first_prefix ++ ["test/support", "#{last}.#{file_ext || "ex"}"])

          [_prefix | leading_rest] ->
            Path.join(
              first_prefix ++ ["test/support" | leading_rest] ++ ["#{last}.#{file_ext || "ex"}"]
            )
        end

      source_folder ->
        Path.join(first_prefix ++ [source_folder | leading] ++ ["#{last}.#{file_ext || "ex"}"])
    end
  end
end
