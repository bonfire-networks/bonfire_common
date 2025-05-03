defmodule Bonfire.Common.Mix.Tasks.Helpers do
  use Bonfire.Common.Config

  def igniter_copy(igniter, source, target, opts \\ [])

  def igniter_copy(igniter, sources, target, opts) when is_list(sources) do
    IO.puts("Batch copying #{inspect(sources)} to #{target}")

    Enum.reduce(sources, igniter, fn source, igniter ->
      igniter_copy(igniter, source, prepare_target_path(source, target), opts)
    end)
  end

  def igniter_copy(igniter, source, target, opts) do
    IO.puts("Copying #{source} to #{target}")

    if File.dir?(source) do
      sources =
        File.ls!(source)
        |> Enum.map(fn file -> Path.join(source, file) end)

      igniter_copy(igniter, sources, target, opts)
    else
      if File.exists?(source) do
        contents_to_copy = File.read!(source)

        if String.contains?(target, "/"), do: File.mkdir_p!(Path.dirname(target))

        Igniter.create_or_update_file(igniter, target, contents_to_copy, fn source ->
          Rewrite.Source.update(source, :content, contents_to_copy)
        end)
      else
        IO.puts("Warning: Source file `#{source}` does not exist")
        igniter
      end
    end
  end

  defp prepare_target_path(source, target) do
    # Remove the repeated part of source from target
    if String.contains?(target, source) do
      String.replace(target, source, "")
      |> String.trim_leading("/")
      |> (&Path.join(target, &1)).()
    else
      Path.join(target, Path.basename(source))
    end
  end

  def list_extensions do
    extensions_pattern =
      Bonfire.Common.Utils.maybe_apply(Bonfire.Mixer, :multirepo_prefixes, [],
        fallback_return: []
      ) ++ ["bonfire"] ++ Bonfire.Common.Config.get([:extensions_pattern], [])

    (Bonfire.Common.Utils.maybe_apply(Bonfire.Mixer, :deps_tree_flat, [], fallback_return: nil) ||
       Bonfire.Common.Extensions.loaded_deps_names())
    # |> IO.inspect(label: "all deps")
    |> Enum.map(&to_string/1)
    |> Enum.filter(fn
      #  FIXME: make this configurable
      "bonfire_" <> _ -> true
      name -> String.starts_with?(name, extensions_pattern)
    end)
  end

  def igniter_path_for_module(
        igniter,
        module_name,
        kind_or_prefix \\ "lib",
        file_ext \\ nil,
        ext_prefix \\ "extensions"
      ) do
    ext_path_for_module(
      module_name,
      kind_or_prefix,
      file_ext,
      ext_prefix,
      igniter
    )
  end

  def ext_path_for_module(
        module_name,
        kind_or_prefix \\ "lib",
        file_ext \\ nil,
        ext_prefix \\ "extensions",
        igniter \\ nil
      ) do
    path =
      case module_name
           |> Module.split() do
        ["Bonfire", ext | rest] -> ["Bonfire#{ext}"] ++ rest
        other -> other
      end
      |> Enum.map(&Macro.underscore/1)

    first = List.first(path)
    last = List.last(path)
    leading = path |> Enum.drop(1) |> Enum.drop(-1)
    path_prefixes = [ext_prefix, first]

    case kind_or_prefix do
      :test ->
        file_ext = file_ext || "exs"

        # TODO: does Igniter proper_location support this?
        if String.ends_with?(last, "_test") do
          ["test" | leading] ++ ["#{last}.#{file_ext}"]
        else
          ["test" | leading] ++ ["#{last}_test.#{file_ext}"]
        end

      "test/support" ->
        file_ext = file_ext || "ex"

        if file_ext == "ex" and igniter do
          Igniter.Project.Module.proper_location(igniter, module_name, :test_support)
        else
          case leading do
            [] ->
              ["test/support", "#{last}.#{file_ext}"]

            [_prefix | leading_rest] ->
              ["test/support" | leading_rest] ++ ["#{last}.#{file_ext}"]
          end
        end

      source_folder ->
        file_ext = file_ext || "ex"

        if file_ext == "ex" and kind_or_prefix == "lib" and igniter do
          Igniter.Project.Module.proper_location(igniter, module_name)
        else
          [source_folder | leading] ++ ["#{last}.#{file_ext}"]
        end
    end
    |> join_prefixes(path_prefixes)
  end

  defp join_prefixes(paths, path_prefixes) do
    Path.join(path_prefixes ++ List.wrap(paths))
  end
end
