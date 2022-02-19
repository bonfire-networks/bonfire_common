defmodule Bonfire.Common.Extensions do

  @prefix "bonfire_"
  @prefix_data "bonfire_data_"

  import Where
  # import Mix.Dep, only: [loaded: 1, format_dep: 1, format_status: 1, check_lock: 1]

  def data() do

    deps = Bonfire.Application.deps() # Bonfire.Common.Extend.loaded_deps()
    #IO.inspect(List.first(deps))

    extensions = filter_bonfire(deps)
    other_deps = filter_bonfire(deps, false)

    schemas = filter_bonfire(extensions, true, @prefix_data)
    extensions = filter_bonfire(extensions, false, @prefix_data)
    #IO.inspect(List.first(extensions))

    [
      extensions: extensions,
      schemas: schemas,
      other_deps: other_deps
    ]
  end


  defp filter_bonfire(deps, only \\ true, prefix \\ @prefix) do
    Enum.filter(deps, fn
      %{app: name} ->
        case Atom.to_string(name) |> String.split(prefix) do
          [_, _] -> only
          _ -> !only
        end
      _ -> !only
    end)
  end

  def get_version(%{scm: Mix.SCM.Path}=dep), do: " (local fork based on "<>get_branch(dep)<>" "<>do_get_version(dep)<>")"
  def get_version(dep), do: do_get_version(dep)

  defp do_get_version(%{status: {:ok, version}}), do: version
  defp do_get_version(%{requirement: version}), do: version
  defp do_get_version(_), do: ""

  def get_branch(%{opts: opts}) when is_list(opts), do: get_branch(Enum.into(opts, %{}))
  def get_branch(%{git: _, branch: branch}), do: branch
  def get_branch(%{lock: {:git, _url, _, [branch: branch]}}), do: branch
  def get_branch(dep), do: ""

  def get_link(%{opts: opts}) when is_list(opts), do: get_link(Enum.into(opts, %{}))
  def get_link(%{hex: hex}), do: "https://hex.pm/packages/#{hex}"
  def get_link(%{lock: {:git, url, _, [branch: branch]}}), do: "#{url}/tree/#{branch}"
  def get_link(%{git: url, branch: branch}), do: "#{url}/tree/#{branch}"
  def get_link(%{lock: {:git, url, _, _}}), do: url
  def get_link(%{git: url}), do: url
  def get_link(dep) do
    IO.inspect(dep)
    "#"
  end

  def get_version_link(%{opts: opts}) when is_list(opts), do: get_version_link(Enum.into(opts, %{}))
  def get_version_link(%{path: file}), do: "/settings/extensions/diff?local="<>file
  def get_version_link(%{lock: {:git, "https://github.com/"<>url, ref, [branch: branch]}}), do: "https://github.com/#{url}/compare/#{ref}...#{branch}"
  def get_version_link(dep), do: get_link(dep)


end
