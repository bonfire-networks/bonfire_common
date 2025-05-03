# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ModuleAnalyzer do
  @moduledoc """
  Common functionality for analyzing the codebase.

  This module provides the core functionality for scanning and analyzing modules across Bonfire applications, serving as a foundation for both the `ExtensionBehaviour` registry and the `ConfigSettingsRegistry`.
  """
  use Untangle
  alias Bonfire.Common.Utils
  use Bonfire.Common.Config
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Extend

  @doc """
  Get all Bonfire-related applications based on name pattern.
  """
  def apps_to_scan(opts \\ []) do
    pattern =
      Utils.maybe_apply(Bonfire.Mixer, :multirepo_prefixes, [], fallback_return: []) ++
        ["bonfire"] ++ Config.get([:extensions_pattern], [])

    Extend.loaded_applications_map(opts)
    |> Enum.map(fn
      {app, {_version, description}} ->
        if String.starts_with?(to_string(app), pattern) or
             String.starts_with?(description, pattern) do
          # TODO: exclude any disabled extensions?
          app
        else
          nil
        end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get all modules from Bonfire-related applications.

  Returns a list of tuples {app_name, [module_list]}
  """
  def app_modules_to_scan(opts \\ []) do
    apps_to_scan(opts)
    |> Enum.map(fn app ->
      case Application.spec(app, :modules) do
        [] ->
          nil

        modules when is_list(modules) ->
          # TODO: exclude any disabled modules?
          {app, modules}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Helper to run a GenServer that populates a persistent term cache.

  This is a common pattern for both registries.
  """
  def populate_registry(module, prepare_fun) do
    Logger.info("Analyzing the codebase for #{inspect(module)}...")

    indexed = prepare_fun.()

    # Store the result in persistent_term for fast global access
    :persistent_term.put(module, indexed)

    indexed
  end

  @doc """
  Filter modules based on a predicate function.

  The predicate should be a function that takes a module and returns true/false.
  """
  def filter_modules(app_modules, predicate) when is_function(predicate, 1) do
    app_modules
    |> Enum.reduce(%{}, fn {app, modules}, acc ->
      filtered_modules = Enum.filter(modules, predicate)

      if Enum.empty?(filtered_modules) do
        acc
      else
        Map.put(acc, app, filtered_modules)
      end
    end)
  end

  @doc """
  Check if a module uses a particular module (via import, alias, or direct calls).

  This implementation analyzes the module's abstract code to detect imports,
  aliases, and module references.
  """
  def module_uses_module?(module, target_module) do
    # Only proceed if the module is loaded
    try do
      case Code.ensure_loaded(module) do
        {:module, _} ->
          # Try to get the module's abstract code
          case get_abstract_code(module) do
            {:ok, abstract_code} ->
              # Check for imports, aliases, and direct module references
              has_import = has_import?(abstract_code, target_module)
              has_alias = has_alias?(abstract_code, target_module)
              has_reference = has_module_reference?(abstract_code, target_module)

              has_import or has_alias or has_reference

            _ ->
              # Fallback to a simpler check using function names
              module_info = module.module_info()
              functions = Keyword.get(module_info, :functions, [])

              target_name =
                target_module
                |> to_string()
                |> String.split(".")
                |> List.last()
                |> String.downcase()

              Enum.any?(functions, fn {name, _} ->
                to_string(name) =~ String.downcase(target_name)
              end)
          end

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  # Helper to get abstract code from a module
  defp get_abstract_code(module) do
    beam_file = :code.which(module)

    case :beam_lib.chunks(beam_file, [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {:raw_abstract_v1, abstract_code}}]}} ->
        {:ok, abstract_code}

      _ ->
        :error
    end
  end

  # Check if the module imports the target module
  defp has_import?(abstract_code, target_module) do
    target_module_str = Atom.to_string(target_module)

    Enum.any?(abstract_code, fn
      {:attribute, _, :import, {imported_module, _funcs, _}} ->
        Atom.to_string(imported_module) == target_module_str

      _ ->
        false
    end)
  end

  # Check if the module aliases the target module
  defp has_alias?(abstract_code, target_module) do
    target_module_parts = Atom.to_string(target_module) |> String.split(".")
    target_module_last = List.last(target_module_parts)

    Enum.any?(abstract_code, fn
      {:attribute, _, :alias, aliases} when is_list(aliases) ->
        Enum.any?(aliases, fn
          {aliased_as, aliased_module, _} ->
            Atom.to_string(aliased_module) == Atom.to_string(target_module) or
              Atom.to_string(aliased_as) == target_module_last

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  # Check for direct references to the target module
  defp has_module_reference?(abstract_code, target_module) do
    target_module_str = Atom.to_string(target_module)

    Enum.any?(abstract_code, fn
      {:function, _, _, _, clauses} ->
        Enum.any?(clauses, fn
          {:clause, _, _, _, exprs} ->
            has_module_in_expr?(exprs, target_module_str)
        end)

      _ ->
        false
    end)
  end

  # Recursively search for module references in expressions
  defp has_module_in_expr?(exprs, target_module_str) when is_list(exprs) do
    Enum.any?(exprs, &has_module_in_expr?(&1, target_module_str))
  end

  defp has_module_in_expr?({:call, _, {:remote, _, {:atom, _, module}, _}, _}, target_module_str) do
    Atom.to_string(module) == target_module_str
  end

  defp has_module_in_expr?({:call, _, _, args}, target_module_str) do
    has_module_in_expr?(args, target_module_str)
  end

  defp has_module_in_expr?({:match, _, pattern, expr}, target_module_str) do
    has_module_in_expr?(pattern, target_module_str) or
      has_module_in_expr?(expr, target_module_str)
  end

  defp has_module_in_expr?({:case, _, expr, clauses}, target_module_str) do
    has_module_in_expr?(expr, target_module_str) or
      Enum.any?(clauses, fn {:clause, _, _, _, body} ->
        has_module_in_expr?(body, target_module_str)
      end)
  end

  defp has_module_in_expr?({:block, _, exprs}, target_module_str) do
    has_module_in_expr?(exprs, target_module_str)
  end

  defp has_module_in_expr?(_, _), do: false

  @doc """
  Extract module info based on a custom extractor function.

  The extractor should be a function that takes a module and returns
  a list of extracted data items or an empty list if nothing is found.
  """
  def extract_from_modules(modules, extractor) when is_function(extractor, 1) do
    modules
    |> Enum.map(fn module ->
      extracted = extractor.(module)
      {module, extracted}
    end)
    |> Enum.filter(fn {_, extracted} -> not Enum.empty?(extracted) end)
    |> Map.new()
  end

  @doc """
  Flatten a hierarchical structure into a list.
  """
  def modules_only(app_modules) do
    app_modules
    |> Enum.flat_map(fn {_app, modules} -> modules end)
  end
end
