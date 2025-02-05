defmodule Bonfire.Common.Mix.Tasks.Helpers do
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
