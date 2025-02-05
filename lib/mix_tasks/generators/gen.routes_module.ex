defmodule Mix.Tasks.Bonfire.Gen.RoutesModule do
  @moduledoc """
  `just mix bonfire.gen.routes_module Bonfire.MyUIExtension`

  will present you with a diff and create new file(s)
  """
  use Igniter.Mix.Task
  alias Bonfire.Common.Mix.Tasks.Helpers

  def igniter(igniter, [module_name | _] = _argv) do
    # app_name = Bonfire.Application.name()

    snake_name = Macro.underscore(module_name)

    ext_module =
      module_name
      |> Macro.camelize()

    module_name =
      ext_module
      |> Kernel.<>(".Web.Routes")
      |> Igniter.Project.Module.parse()

    # |> IO.inspect()

    lib_path_prefix = "lib/web"

    igniter
    |> Igniter.create_new_file(
      Helpers.igniter_path_for_module(igniter, module_name, lib_path_prefix),
      """
      defmodule #{inspect(module_name)} do
        @behaviour Bonfire.UI.Common.RoutesModule

        defmacro __using__(_) do
          quote do
            # pages anyone can view
            scope "/#{snake_name}/", #{ext_module} do
              pipe_through(:browser)

              live("/", HomeLive)
            end

            # pages only guests can view
            scope "/#{snake_name}/", #{ext_module} do
              pipe_through(:browser)
              pipe_through(:guest_only)
            end

            # pages you need an account to view
            scope "/#{snake_name}/", #{ext_module} do
              pipe_through(:browser)
              pipe_through(:account_required)
            end

            # pages you need to view as a user
            scope "/#{snake_name}/", #{ext_module} do
              pipe_through(:browser)
              pipe_through(:user_required)
            end

            # pages only admins can view
            scope "/#{snake_name}/admin", #{ext_module} do
              pipe_through(:browser)
              pipe_through(:admin_required)
            end
          end
        end
      end
      """
    )
  end
end
