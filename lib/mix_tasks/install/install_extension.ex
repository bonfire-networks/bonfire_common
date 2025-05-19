if Code.ensure_loaded?(Igniter.Mix.Task) do
defmodule Mix.Tasks.Bonfire.Install.Extension do
  import Bonfire.Common.Extend
  use_if_enabled Igniter.Mix.Task
     alias Bonfire.Common.Mix.Tasks.Helpers
  alias Mess.Janitor

  # TODO: turn into an escript so it can be run without compiling the whole app?

  @shortdoc "Install an extension into the parent app"
  @doc """
  Usage:
  `just mix bonfire.install.extension hex my_extension@1.0`
  or
  `just mix bonfire.install.extension git my_extension@https://my.git/extension_repo`
  or
  `just mix bonfire.install.extension clone my_extension@https://my.git/extension_repo`
  """

  @switches [force: :boolean]
  @default_config_path "config"

  def igniter(igniter, [type | args]) do
    # IO.inspect(args, label: "Args")

    case OptionParser.parse(args, switches: @switches) do
      {_opts, [], _} ->
        raise "No extension specified"

      {opts, extensions_with_source_or_version, _} ->
        install(igniter, type, extensions_with_source_or_version, opts)
    end
  end

  def install(igniter, type, extensions_with_source_or_version, opts)
      when is_list(extensions_with_source_or_version) do
    extensions =
      Enum.map(extensions_with_source_or_version, fn v ->
        [extension, version_or_source] = String.split(v, "@")
        {extension, version_or_source}
      end)

    extension_names = Enum.map(extensions, fn {extension, _} -> extension end)

    Enum.reduce(extensions, igniter, fn {extension, version_or_source}, igniter ->
      add_dep(type, extension, version_or_source, opts)
    end)

    fetch_and_run_installers(igniter, extension_names, opts)
  end

  def add_dep(type, extension, version_or_source, opts) do
    defs =
      opts[:defs] ||
        [
          path: "config/current_flavour/deps.path",
          git: "config/current_flavour/deps.git",
          hex: "config/current_flavour/deps.hex"
        ]

    :ok =
      case type do
        "hex" ->
          Janitor.add(extension, version_or_source, :hex, defs[:hex])

        "git" ->
          Janitor.add(extension, version_or_source, :git, defs[:git])

        "clone" ->
          Janitor.clone(extension, version_or_source, defs: defs)

        _ ->
          raise "Unknown extension type: #{type}"
      end
  end

  def fetch_and_run_installers(igniter, extension_names, opts) when is_list(extension_names) do
    igniter =
      Igniter.Util.Install.get_deps!(
        igniter,
        Keyword.put_new(opts, :operation, "installing new dependencies")
      )

    #  default_task = Mix.Tasks.Bonfire.Extension.Installer

    available_tasks =
      Enum.zip(extension_names, Enum.map(extension_names, &Mix.Task.get("#{&1}.install")))

    # |> Enum.map(fn {extension, source_task} -> 
    #   {extension, source_task || default_task} 
    # end)

    case available_tasks do
      [] ->
        :ok

      tasks ->
        msg = "\nInstalling:\n\n#{Enum.map_join(extension_names, "\n", &"* #{&1}")}"
        IO.puts(msg)

        run_installers(
          igniter,
          tasks,
          msg,
          opts,
          opts
        )
    end

    igniter
  end

  # NOTE: copied from Igniter, TODO: PR to make public function there
  defp run_installers(igniter, igniter_task_sources, title, argv, options) do
    igniter_task_sources
    |> Enum.reduce(igniter, fn {name, task}, igniter ->
      if is_nil(task) do
        igniter = Igniter.compose_task(igniter, Mix.Tasks.Bonfire.Extension.Installer, [name])
      else
        igniter = Igniter.compose_task(igniter, task, argv)
      end

      Mix.shell().info("`#{name}.install` #{IO.ANSI.green()}✔#{IO.ANSI.reset()}")
      igniter
    end)
    |> Igniter.do_or_dry_run(Keyword.put(options, :title, title))
  end
end
end