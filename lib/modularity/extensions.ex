defmodule Bonfire.Common.Extensions do
  @prefix "bonfire_"
  @prefix_ui "bonfire_ui_"
  @prefix_data "bonfire_data_"

  import Untangle
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Extend

  # import Mix.Dep, only: [loaded: 1, format_dep: 1, format_status: 1, check_lock: 1]

  def global_disable(extension) do
    global_toggle(extension, true)
  end

  def global_enable(extension) do
    global_toggle(extension, nil)
  end

  defp global_toggle(extension, enabled?) do
    put =
      Bonfire.Me.Settings.put([extension, :disabled], enabled?,
        scope: :instance,
        skip_boundary_check: true
      )

    # generate an updated reverse router based on extensions that are enabled/disabled
    Bonfire.Common.Extend.generate_reverse_router!()

    put
  end

  def data() do
    # use compiled-time cached list
    deps = Bonfire.Application.deps(:flat)

    # TODO: refactor using `Enum.split_with/2`

    feature_extensions = filter_bonfire(deps, true, @prefix)
    other_deps = filter_bonfire(deps, false, @prefix)

    ecosystem_libs = filter_bonfire(other_deps, true, :git)
    other_deps = filter_bonfire(other_deps, false, :git)

    ui = filter_bonfire(feature_extensions, true, @prefix_ui)
    feature_extensions = filter_bonfire(feature_extensions, false, @prefix_ui)

    schemas = filter_bonfire(feature_extensions, true, @prefix_data)
    feature_extensions = filter_bonfire(feature_extensions, false, @prefix_data)

    [
      feature_extensions: feature_extensions,
      ui: ui,
      schemas: schemas,
      ecosystem_libs: ecosystem_libs,
      other_deps: other_deps
    ]
  end

  def loaded_deps(opts \\ [])

  def loaded_deps(:nested) do
    # note that you should call the compile-time cached list in Bonfire.Application
    if Extend.module_enabled?(Mix.Dep) do
      {func, args} = loaded_deps_func_name()
      apply(Mix.Dep, func, args)
      # |> IO.inspect
    else
      # Note: we cache this at compile-time in `Bonfire.Application` so it is available in releases
      []
    end
  end

  def loaded_deps(opts) do
    # note that you should call the compile-time cached list in Bonfire.Application
    (opts[:deps_loaded] || loaded_deps(:nested))
    |> prepare_list(opts)
    |> List.flatten()
    |> Enum.uniq_by(&dep_name(&1))
  end

  defp prepare_list(deps, opts) when is_list(deps) do
    Enum.flat_map(deps, fn
      %Mix.Dep{deps: nested_deps} = dep ->
        [dep] ++ prepare_list(nested_deps, opts)

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

  defp filter_bonfire(deps, only, prefix) when is_binary(prefix) do
    Enum.filter(deps, fn
      %{app: name} ->
        case Atom.to_string(name) |> String.split(prefix) do
          [_, _] -> only
          _ -> !only
        end

      _ ->
        !only
    end)
  end

  defp filter_bonfire(deps, only, :git) do
    Enum.filter(deps, fn
      %{} = dep ->
        # debug(dep)
        repo =
          Utils.e(dep, :opts, :git, nil) ||
            Utils.e(dep, :opts, :lock, {nil, nil}) |> elem(1)

        # debug(repo)
        if is_binary(repo) and String.contains?(repo, "bonfire"),
          do: only,
          else: !only

      _ ->
        !only
    end)
  end

  def get_version(%{scm: Mix.SCM.Path} = dep),
    do:
      " (local fork based on " <>
        get_branch(dep) <> " " <> do_get_version(dep) <> ")"

  def get_version(dep), do: do_get_version(dep)

  defp do_get_version(%{status: {:ok, version}}), do: version
  defp do_get_version(%{requirement: version}), do: version
  defp do_get_version(_), do: ""

  def get_branch(%{opts: opts}) when is_list(opts),
    do: get_branch(Enum.into(opts, %{}))

  def get_branch(%{git: _, branch: branch}), do: branch
  def get_branch(%{lock: {:git, _url, _, [branch: branch]}}), do: branch
  def get_branch(_dep), do: ""

  def get_link(%{opts: opts}) when is_list(opts),
    do: get_link(Enum.into(opts, %{}))

  def get_link(%{hex: hex}), do: "https://hex.pm/packages/#{hex}"

  def get_link(%{lock: {:git, url, _, [branch: branch]}}),
    do: "#{url}/tree/#{branch}"

  def get_link(%{lock: {:git, url, _, _}}), do: url
  def get_link(%{git: url, branch: branch}), do: "#{url}/tree/#{branch}"
  def get_link(%{git: url}), do: url

  def get_link(dep) do
    warn(dep, "dunno how")
    "#"
  end

  def get_code_link(%{app: app}),
    do: "/settings/extensions/code/#{app}"

  def get_code_link(dep), do: get_version_link(dep)


  def get_version_link(%{opts: opts}) when is_list(opts),
    do: get_version_link(Enum.into(opts, %{}))

  def get_version_link(%{path: file, lock: {:git, _, ref, [branch: branch]}}),
    do: "/settings/extensions/diff?ref=#{ref || branch}&local=#{file}"

  def get_version_link(%{path: file}),
    do: "/settings/extensions/diff?local=#{file}"

  def get_version_link(%{
        lock: {:git, "https://github.com/" <> url, ref, [branch: branch]}
      }),
      do: "https://github.com/#{url}/compare/#{ref}...#{branch}"

  def get_version_link(dep), do: get_link(dep)

  defp dep_name(%Mix.Dep{app: dep}) when is_atom(dep), do: dep
  defp dep_name(dep) when is_tuple(dep), do: elem(dep, 0) |> dep_name()
  defp dep_name(dep) when is_atom(dep), do: dep
  defp dep_name(dep) when is_binary(dep), do: dep
end
