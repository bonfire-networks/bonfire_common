if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.Bonfire.Extension.Installer do
    import Bonfire.Common.Extend
    use_if_enabled(Igniter.Mix.Task)
    alias Bonfire.Common.Mix.Tasks.Helpers

    # TODO: turn into an escript so it can be run without compiling the whole app?

    @shortdoc "Install an extension into the parent app"

    @doc """
    Usage:
    `just mix bonfire.install.extension my_extension`
    """

    @default_config_path "config"

    def igniter(igniter, args) do
      # IO.inspect(args, label: "Args")

      install(igniter, args)
    end

    def install(igniter, args) do
      igniter
      |> Igniter.compose_task(Mix.Tasks.Bonfire.Install.CopyConfigs, args)
      |> Igniter.compose_task(Mix.Tasks.Bonfire.Install.CopyMigrations, args)
    end
  end
end
