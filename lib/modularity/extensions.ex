defmodule Bonfire.Common.Extensions do
  @moduledoc """
  Helpers for managing Bonfire extensions, e.g., enabling/disabling a module or extension,
  or listing available extensions and their metadata.
  """

  @prefix "bonfire"
  @prefix_ui "bonfire_ui_"
  @prefix_data "bonfire_data_"

  import Untangle
  use Bonfire.Common.E
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Extend

  # import Mix.Dep, only: [loaded: 1, format_dep: 1, format_status: 1, check_lock: 1]

  @doc """
  Disables a given extension globally.

  ## Parameters
    - `extension`: The name of the extension to disable.

  ## Examples

      > {:ok, %Bonfire.Data.Identity.Settings{json: %{bonfire: %{my_test_extension: %{modularity: :disabled}}}}} =  Bonfire.Common.Extensions.global_disable(:my_test_extension)
  """
  def global_disable(extension) do
    global_toggle(extension, false)
  end

  @doc """
  Enables a given extension globally.

  ## Parameters
    - `extension`: The name of the extension to enable.

  ## Examples

      > {:ok, %Bonfire.Data.Identity.Settings{json: %{bonfire: %{my_test_extension: %{modularity: nil}}}}} = Bonfire.Common.Extensions.global_enable(:my_test_extension)
  """
  def global_enable(extension) do
    global_toggle(extension, true)
  end

  defp global_toggle(extension, enable?) do
    set = if !enable?, do: :disabled

    put =
      Bonfire.Common.Settings.put([extension, :modularity], set,
        scope: :instance,
        skip_boundary_check: true
      )

    # generate an updated reverse router based on extensions that are enabled/disabled
    Bonfire.Common.Extend.generate_reverse_router!()

    put
  end

  @doc """
  Retrieves a list of all dependencies.

  ## Examples

      > Bonfire.Common.Extensions.all_deps()
      [%Mix.Dep{...}, %Mix.Dep{...}]
  """
  def all_deps, do: loaded_deps(:flat)

  def data() do
    deps = all_deps()

    required_deps = Bonfire.Application.required_deps()

    # TODO: refactor using `Enum.split_with/2`

    {required, other_deps} =
      Enum.split_with(deps, fn dep -> to_string(dep.app) in required_deps end)

    {feature_extensions, other_deps} =
      Enum.split_with(other_deps, fn dep -> is_bonfire_ext?(dep, @prefix) end)

    # feature_extensions =
    #   Enum.map(
    #     feature_extensions,
    #     &Map.put(&1, :extra, Bonfire.Common.ExtensionModule.extension(&1.app))
    #   )

    {schemas, feature_extensions} =
      Enum.split_with(feature_extensions, fn dep -> is_bonfire_ext?(dep, @prefix_data) end)

    {ui, feature_extensions} =
      Enum.split_with(feature_extensions, fn dep -> is_bonfire_ext?(dep, @prefix_ui) end)

    {ecosystem_libs, other_deps} =
      Enum.split_with(other_deps, fn dep -> is_bonfire_ext?(dep, :git) end)

    [
      required: required,
      feature_extensions: feature_extensions,
      ui: ui,
      schemas: schemas,
      ecosystem_libs: ecosystem_libs,
      other_deps: other_deps
    ]
  end

  @doc """
  Retrieves a list of all dependencies in a specific format based on the options provided.

  ## Parameters
    - `opts`: Options to determine the format, e.g., `:flat`, `:tree_flat`, `:nested`.

  ## Examples

      > Bonfire.Common.Extensions.loaded_deps(:flat)
      [%Mix.Dep{}, %Mix.Dep{}, ...]

      > Bonfire.Common.Extensions.loaded_deps(:tree_flat)
      [%Mix.Dep{}, %Mix.Dep{}, ...]
  """
  def loaded_deps(opts \\ [])

  def loaded_deps(:flat) do
    loaded_deps(
      deps_loaded: loaded_deps(:nested)
      # deps_tree_flat: loaded_deps(:tree_flat)
    )
  end

  def loaded_deps(:tree_flat) do
    # note that you should call the compile-time cached list in Bonfire.Application
    if Code.ensure_loaded?(Bonfire.Mixer) do
      Bonfire.Mixer.deps_tree_flat()
    else
      # Note: we cache this at compile-time in `Bonfire.Application` so it is available in releases
      Bonfire.Application.deps(:tree_flat)
    end
  end

  def loaded_deps(:nested) do
    # note that you should call the compile-time cached list in Bonfire.Application
    if Code.ensure_loaded?(Mix.Dep) do
      {func, args} = loaded_deps_func_name()
      apply(Mix.Dep, func, args)
      # |> IO.inspect
    else
      # Note: we cache this at compile-time in `Bonfire.Application` so it is available in releases
      Bonfire.Application.deps(:nested)
    end
  end

  def loaded_deps(opts) do
    prepare_loaded_deps(opts)
    |> Enum.uniq_by(&dep_name(&1))
  end

  @doc """
  Retrieves a list of all dependency names in a specific format based on the options provided.

  ## Parameters
    - `opts`: Options to determine the format, e.g., `:flat`, `:tree_flat`, `:nested`.

  ## Examples

      > Bonfire.Common.Extensions.loaded_deps_names()
      [:dep1, :dep2]
  """
  def loaded_deps_names(opts \\ []) do
    prepare_loaded_deps(opts)
    |> Enum.map(&dep_name(&1))
    |> Enum.uniq()
  end

  defp prepare_loaded_deps(opts \\ []) do
    # note that you should call the compile-time cached list in Bonfire.Application
    ((opts[:deps_loaded] || loaded_deps(:nested)) ++
       (opts[:deps_tree_flat] || []))
    # |> IO.inspect(limit: :infinity, label: "to prepare")
    |> prepare_list()
    |> List.flatten()
    |> Enum.uniq_by(&dep_name(&1))

    # |> IO.inspect(label: "prepared")
  end

  defp prepare_list(deps) when is_list(deps) do
    Enum.flat_map(deps, fn
      %Mix.Dep{deps: nested_deps} = dep ->
        [Map.put(dep, :deps, nil)] ++ prepare_list(nested_deps)

      dep ->
        [dep]
    end)
  end

  defp loaded_deps_func_name() do
    if Keyword.has_key?(Mix.Dep.__info__(:functions), :cached) do
      {:cached, []}
    else
      {:loaded, [[]]}
    end
  end

  defp filter_bonfire(deps, only, prefix) do
    Enum.filter(deps, fn
      dep ->
        is_bonfire_ext?(dep, prefix, only)
    end)
  end

  defp is_bonfire_ext?(dep, prefix, only \\ true)

  defp is_bonfire_ext?(dep, prefix, only) when is_binary(prefix) do
    case dep do
      %{app: name} ->
        case Atom.to_string(name) |> String.split(prefix) do
          [_, _] -> only
          _ -> !only
        end

      _ ->
        !only
    end
  end

  defp is_bonfire_ext?(dep, :git, only) do
    case dep do
      %{} ->
        # debug(dep)
        repo =
          e(dep, :opts, :git, nil) ||
            e(dep, :opts, :lock, {nil, nil}) |> elem(1)

        # debug(repo)
        if is_binary(repo) and String.contains?(repo, "bonfire"),
          do: only,
          else: !only

      _ ->
        !only
    end
  end

  @doc """
  Outputs the current version string for a dependency.

  ## Parameters
    - `dep`: The dependency from which to get the version.

  ## Examples

      iex> Bonfire.Common.Extensions.get_version(%{status: {:ok, "1.0.0"}})
      "1.0.0"

      iex> Bonfire.Common.Extensions.get_version(%{requirement: ">= 1.0.0"})
      ">= 1.0.0"
  """
  def get_version(%{scm: Mix.SCM.Path} = dep),
    do:
      "forked from " <>
        get_branch(dep) <> " " <> do_get_version(dep)

  def get_version(dep), do: do_get_version(dep)

  defp do_get_version(%{status: {:ok, version}}), do: version
  defp do_get_version(%{requirement: version}), do: version
  defp do_get_version(_), do: ""

  @doc """
  Retrieves the branch name for a dependency.

  ## Parameters
    - `dep`: The dependency from which to get the branch.

  ## Examples

      iex> Bonfire.Common.Extensions.get_branch(%{git: nil, branch: "main"})
      "main"

      iex> Bonfire.Common.Extensions.get_branch(%{lock: {:git, nil, nil, [branch: "feature"]}})
      "feature"
  """
  def get_branch(%{opts: opts}) when is_list(opts),
    do: get_branch(Enum.into(opts, %{}))

  def get_branch(%{git: _, branch: branch}), do: branch
  def get_branch(%{lock: {:git, _url, _, [branch: branch]}}), do: branch
  def get_branch(_dep), do: ""

  @doc """
  Returns a link to the package or repository of a dependency.

  ## Parameters
    - `dep`: The dependency from which to generate the link.

  ## Examples

      iex> Bonfire.Common.Extensions.get_link(%{hex: "example_package"})
      "https://hex.pm/packages/example_package"

      iex> Bonfire.Common.Extensions.get_link(%{git: "https://github.com/user/repo", branch: "main"})
      "https://github.com/user/repo/tree/main"
  """
  def get_link(%{app: app, opts: opts}) when is_list(opts),
    do: get_link(Enum.into(opts, %{app: app}))

  def get_link(%{hex: hex}), do: "https://hex.pm/packages/#{hex}"

  def get_link(%{lock: {:git, url, _, [branch: branch]}}),
    do: "#{url}/tree/#{branch}"

  def get_link(%{lock: {:git, url, _, _}}), do: url
  def get_link(%{git: url, branch: branch}), do: "#{url}/tree/#{branch}"
  def get_link(%{git: url}), do: url

  def get_link(dep) do
    warn(dep, "dunno how")
    nil
    # "#"
  end

  @doc """
  Constructs a link to the code of a dependency.

  ## Parameters
    - `dep`: The dependency from which to generate the link.

  ## Examples

      iex> Bonfire.Common.Extensions.get_code_link(%{app: "my_app"})
      "/settings/extensions/code/my_app"
  """
  def get_code_link(%{app: app}),
    do: "/settings/extensions/code/#{app}"

  def get_code_link(dep), do: get_version_link(dep)

  @doc """
  Constructs a link to the version of a dependency.

  ## Parameters
    - `dep`: The dependency from which to generate the version link.

  ## Examples

      iex> Bonfire.Common.Extensions.get_version_link(%{app: "my_app", path: "file.ex"})
      "/settings/extensions/diff?app=my_app&local=file.ex"

      iex> Bonfire.Common.Extensions.get_version_link(%{lock: {:git, "https://github.com/user/repo", "abc123", [branch: "main"]}})
      "https://github.com/user/repo/compare/abc123...main"
  """
  def get_version_link(%{app: app, opts: opts}) when is_list(opts),
    do: get_version_link(Enum.into(opts, %{app: app}))

  def get_version_link(%{app: app, path: file, lock: {:git, _, ref, [branch: branch]}}),
    do: "/settings/extensions/diff?app=#{app}&ref=#{ref || branch}&local=#{file}"

  def get_version_link(%{app: app, path: file}),
    do: "/settings/extensions/diff?app=#{app}&local=#{file}"

  def get_version_link(%{
        lock: {:git, "https://github.com/" <> url, ref, [branch: branch]}
      }),
      do: "https://github.com/#{url}/compare/#{ref}...#{branch}"

  def get_version_link(dep), do: get_link(dep)

  @doc """
  Extracts the dependency name from a `Mix.Dep` struct or similar data.

  ## Parameters
    - `dep`: The dependency from which to extract the name.

  ## Examples

      iex> Bonfire.Common.Extensions.dep_name(%Mix.Dep{app: :my_app})
      :my_app

      iex> Bonfire.Common.Extensions.dep_name(:my_app)
      :my_app

      iex> Bonfire.Common.Extensions.dep_name("my_app")
      "my_app"
  """
  def dep_name(%Mix.Dep{app: dep}) when is_atom(dep), do: dep
  def dep_name(dep) when is_tuple(dep), do: elem(dep, 0) |> dep_name()
  def dep_name(dep) when is_atom(dep), do: dep
  def dep_name(dep) when is_binary(dep), do: dep
end
