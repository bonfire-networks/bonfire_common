# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ConfigSettingsRegistry do
  @moduledoc """
  Registry for configuration and settings keys.
  """
  use GenServer, restart: :transient
  use Untangle
  import Bonfire.Common.Utils
  Bonfire.Common.Utils.__common_utils__()
  Bonfire.Common.Utils.__localise__()

  alias Bonfire.Common.Extend
  alias Bonfire.Common.ModuleAnalyzer

  @doc """
  Prepare data structure for the cache.
  """
  def prepare_data_for_cache() do
    # Get compile-time collected keys
    keys = find_registered_keys()

    # Group by type and merge multiple occurrences of the same keys
    config_keys =
      keys
      |> Enum.filter(&(&1.type == :config))
      |> group_keys_by_occurrence()

    settings_keys =
      keys
      |> Enum.filter(&(&1.type == :settings))
      |> group_keys_by_occurrence()

    # Build the result structure
    %{
      config_keys: config_keys,
      settings_keys: settings_keys
    }
  end

  @doc """
  Group keys by their occurrence, preserving all locations where they are defined.
  This ensures we don't lose information when the same key is defined in multiple places.
  """
  def group_keys_by_occurrence(keys) do
    keys
    |> Enum.group_by(& &1.keys)
    |> Enum.map(fn {keys, entries} ->
      env = List.first(entries)[:env]
      # |> debug("env")
      evaluated_keys = if env, do: evaluate_ast(keys, env: env), else: keys

      # Process each entry to evaluate AST values
      processed_entries =
        Enum.map(entries, fn entry ->
          env = entry[:env]
          # |> debug("env_l")

          # Evaluate stored AST if we have an environment
          evaluated_default =
            if env, do: evaluate_ast(entry[:default], env: env), else: entry[:default]

          evaluated_opts = if env, do: evaluate_ast(entry[:opts], env: env), else: entry[:opts]

          # Create a new entry with evaluated values
          %{
            module: env.module,
            file: env.file,
            line: env.line,
            function: env.function,
            default: evaluated_default,
            opts: evaluated_opts
          }
        end)

      # Get all default values that are not nil
      defaults =
        Enum.map(processed_entries, & &1[:default])
        |> Enum.reject(&is_nil/1)

      # Get unique default values
      unique_defaults = Enum.uniq(defaults)

      # Only set default if all entries have the same default value
      common_default =
        if length(unique_defaults) == 1 do
          List.first(unique_defaults)
        else
          nil
        end

      # Merge all opts into a single keyword list
      merged_opts =
        processed_entries
        |> Enum.map(& &1[:opts])
        |> Bonfire.Common.Enums.deep_merge_reduce()

      {evaluated_keys,
       %{
         keys: evaluated_keys,
         locations: processed_entries,
         # Only set default if all entries have the same default
         default: common_default,
         # Merged opts from all occurrences
         opts: merged_opts,
         # Include all unique defaults
         defaults: unique_defaults
       }}
    end)
    |> Map.new()
  end

  @doc """
  Find all registered keys from modules.
  """
  def find_registered_keys() do
    modules = ModuleAnalyzer.app_modules_to_scan()

    # Filter for modules that called get
    modules_with_keys =
      ModuleAnalyzer.filter_modules(
        modules,
        fn module ->
          Code.ensure_loaded?(module) &&
            function_exported?(module, :__bonfire_config_keys__, 0)
        end
      )
      |> debug("modules_with_keys")

    # Collect all registered keys
    Enum.flat_map(modules_with_keys, fn {_app, modules} ->
      Enum.flat_map(modules, fn module ->
        try do
          module.__bonfire_config_keys__()
        rescue
          _ -> []
        end
      end)
    end)
  end

  # GenServer callbacks

  @spec start_link(ignored :: term) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def init(_) do
    populate()
    :ignore
  end

  @doc "Access the cached data, or re-populate if not available"
  def cached_data do
    :persistent_term.get(__MODULE__)
  rescue
    _ in ArgumentError ->
      populate()
      :persistent_term.get(__MODULE__)
  end

  @doc "Rebuild the config/settings registry"
  def populate do
    ModuleAnalyzer.populate_registry(__MODULE__, &prepare_data_for_cache/0)
  end

  # API functions

  @doc "Get all configuration keys and their metadata"
  def config_keys do
    cached_data().config_keys
  end

  @doc "Get all settings keys and their metadata"
  def settings_keys do
    cached_data().settings_keys
  end

  @doc "Get all keys (both config and settings)"
  def all_keys do
    %{
      config: config_keys(),
      settings: settings_keys()
    }
  end

  @doc "Format the registry for display/documentation"
  def format_registry do
    %{
      config:
        Enum.map(config_keys(), fn {keys, data} ->
          %{
            keys: keys,
            default: data.default,
            defaults: data.defaults || [],
            opts: data.opts,
            locations:
              Enum.map(data.locations || [], fn loc ->
                %{
                  module: inspect(loc.module),
                  file: loc.file,
                  line: loc.line,
                  default: loc.default,
                  opts: loc.opts
                }
              end)
          }
        end),
      settings:
        Enum.map(settings_keys(), fn {keys, data} ->
          %{
            keys: keys,
            default: data.default,
            defaults: data.defaults || [],
            opts: data.opts,
            locations:
              Enum.map(data.locations || [], fn loc ->
                %{
                  module: inspect(loc.module),
                  file: loc.file,
                  line: loc.line,
                  default: loc.default,
                  opts: loc.opts
                }
              end)
          }
        end)
    }
  end

  @doc """
  Format the registry for display/documentation
  """

  # Common AST processing logic shared between evaluate_ast and simplified_ast
  defp process_ast(ast, opts \\ []) do
    processor = opts[:processor] || (& &1)
    env = opts[:env]
    on_error = opts[:on_error] || (&format_ast/1)

    try do
      debug(ast, "processing")

      case ast do
        # Skip literals that don't need processing
        literal
        when is_atom(literal) or is_number(literal) or is_binary(literal) or is_boolean(literal) or
               is_nil(literal) or literal == [] or literal == %{} ->
          literal

        # Handle l("text") functions - extract the string
        {:l, _, [text]} when is_binary(text) ->
          localise_dynamic(text)

        {:*, _, args} ->
          Enum.map(args, &process_ast(&1, opts))

        # Handle assigns.__context__
        {{:., _, [{:assigns, _, _}, :__context__]}, _, _} ->
          {:__context__, nil}

        {:assigns, _, [{:socket, _, nil}]} ->
          {:assigns, nil}

        {:., _, [{:assigns, _, nil}, assign_name]} when is_atom(assign_name) ->
          #   "@#{assign_name}"
          {assign_name, nil}

        {{:., _, [{:assigns, _, nil}, assign_name]}, _, []} when is_atom(assign_name) ->
          # "@#{assign_name}"
          {assign_name, nil}

        {:current_user, _,
         [
           {{:., _, [{:assigns, _, nil}, _]}, _, _}
         ]} ->
          {:current_user, nil}

        # Handle function calls like Keyword.merge
        {{:., _, [:Keyword, :merge]}, _, [list1, list2]} = ast ->
          try do
            processed_list1 = process_ast(list1, opts)
            processed_list2 = process_ast(list2, opts)

            if is_list(processed_list1) and is_list(processed_list2) and
                 Keyword.keyword?(processed_list1) and Keyword.keyword?(processed_list2) do
              Keyword.merge(processed_list1, processed_list2)
            else
              warn("not valid keyword lists")
              on_error.(ast, env: env)
            end
          rescue
            e ->
              warn(e, "Could not merge")
              debug(__STACKTRACE__, "failed trace")
              on_error.(ast, env: env)
          end

        # Handle module function calls
        {{:., _, [mod, fun]}, _, args}
        when (is_atom(mod) or is_tuple(mod)) and is_atom(fun) and is_list(args) ->
          debug(mod, "mod_fun_args")

          if(is_atom(mod), do: mod, else: process_ast(mod, opts))
          |> case do
            :error ->
              warn(mod, "Could not find module")
              on_error.(ast, env: env)

            module ->
              function = if is_atom(fun), do: fun, else: process_ast(fun, opts)

              processed_args =
                Enum.map(args, &process_ast(&1, opts))
                |> debug("processed_args")

              # Try to apply the function
              try do
                apply(module, function, processed_args)
              rescue
                e ->
                  warn(e, "Could not apply mfa")
                  debug(__STACKTRACE__, "failed trace")
                  on_error.(ast, env: env)
              end
          end

        {{:., _, [mod, fun]}} when (is_atom(mod) or is_tuple(mod)) and is_atom(fun) ->
          debug(mod, "mod_fun")

          if(is_atom(mod), do: mod, else: process_ast(mod, opts))
          |> case do
            :error ->
              warn(mod, "Could not find module")
              on_error.(ast, env: env)

            module ->
              function = if is_atom(fun), do: fun, else: process_ast(fun, opts)

              # Try to apply the function
              try do
                apply(module, function, [])
              rescue
                e ->
                  warn(e, "Could not apply mfa")
                  debug(__STACKTRACE__, "failed trace")
                  on_error.(ast, env: env)
              end
          end

        {__MODULE__, _, nil} when not is_nil(env) ->
          env.module

        {:__aliases__, _, parts} ->
          debug(parts, "aliases")
          # use_aliases(ast, env)
          use_alias(env, parts)

        # Handle function call with no module, like l("string")
        # {fun, _, args} when is_atom(fun) and is_list(args) ->
        #   debug(fun, "fun")

        #   # For l() function specifically
        #   if fun == :l && length(args) == 1 && is_binary(hd(args)) do
        #     localise_dynamic(hd(args))
        #   else
        #       try do
        #         processed_args = Enum.map(args, &process_ast(&1, opts))
        #         apply(fun, processed_args)
        #       rescue
        #         e -> 
        #         warn(e, "Could not apply fa")
        #         debug(__STACKTRACE__, "failed trace")
        #         on_error.(ast, env: env)
        #       end

        #   end

        # Process lists (including keyword lists) recursively
        {{:., _, list}} when is_list(list) ->
          debug(":. with list")
          process_ast_list(list, opts)

        # Process lists (including keyword lists) recursively
        list when is_list(list) ->
          debug("list")
          process_ast_list(list, opts)

        # Handle maps
        map when is_map(map) ->
          debug("map")

          for {k, v} <- map, into: %{} do
            {process_ast(k, opts), process_ast(v, opts)}
          end

        {:%{}, _, map} when is_list(map) ->
          debug("map_ast")

          for {k, v} <- map, into: %{} do
            {process_ast(k, opts), process_ast(v, opts)}
          end

        {atom, _, nil} when is_atom(atom) ->
          atom

        # For all other AST expressions in evaluate mode
        _ast_expr when not is_nil(env) ->
          debug("other with env")

          try do
            # pass empty assings to avoid `undefined variable "assigns"` error with UI code
            {result, _} =
              Code.eval_quoted(
                ast,
                [assigns: %{}, socket: nil, conn: nil, __context__: %{}, socket_assigns: []],
                env
              )

            result
          rescue
            e ->
              warn(e, "Could not eval")
              debug(__STACKTRACE__, "failed trace")
              on_error.(ast, env: env)
          end

        # Handle tuples that are not AST
        tuple when is_tuple(tuple) ->
          debug("tuple")

          tuple
          |> Tuple.to_list()
          |> Enum.map(&process_ast(&1, opts))
          |> List.to_tuple()

        # Default case - keep as is or apply custom processor
        value ->
          debug("no match")
          processor.(value)
      end
      |> debug("processed")
    rescue
      e ->
        warn(e, "Could not process")
        debug(__STACKTRACE__, "failed trace")
        on_error.(ast, env: env)
    end
  end

  # Helper to safely evaluate AST at compile time
  defp evaluate_ast(nil, _), do: nil

  defp evaluate_ast(ast, opts) do
    process_ast(
      ast,
      Keyword.put(opts, :on_error, fn failed_ast, opts ->
        simplified_ast(failed_ast, opts)
      end)
    )
  end

  # Create a simplified view of AST for display
  defp simplified_ast(nil, _), do: nil

  defp simplified_ast(ast, opts) do
    process_ast(
      ast,
      Keyword.put(opts, :on_error, fn failed_ast, _opts ->
        format_ast(failed_ast)
      end)
    )
  end

  defp process_ast_list(list, opts) do
    do_process_ast_list(
      list,
      &process_ast(&1, opts),
      fn {k, v} -> {k, process_ast(v, opts)} end
    )
  end

  # Helper function to process lists consistently in both evaluate_ast and simplified_ast
  defp do_process_ast_list(list, item_processor, kv_processor) do
    if Keyword.keyword?(list) do
      debug("kw")
      Enum.map(list, kv_processor)
    else
      debug("list")
      Enum.map(list, item_processor)
    end
  end

  @doc """
  Process keys for registration to make them more human-readable.
  """
  defp format_ast(keys) do
    keys
    |> Extend.prettify_ast()
    |> Extend.simplify_ast()
  end

  defp use_alias(env, parts) do
    env.aliases
    # |> debug("all_aliases")
    |> Enum.filter(fn {as, fqn} ->
      Module.concat([as]) == Module.concat(parts)
    end)
    # |> Enum.filter(fn {_as, fqn} ->
    #   fqn_split = Module.split(fqn)
    #   |> Enum.map(&String.to_existing_atom/1)
    #   |> debug("fqn")

    #   List.starts_with?(parts, fqn_split)
    # end)
    |> Enum.sort_by(fn {_as, fqn} ->
      fqn
      |> Module.split()
      |> Enum.count()
    end)
    |> Enum.reverse()
    |> Enum.at(0)
    |> debug("result")
    |> case do
      nil ->
        maybe_without_alias = Module.concat([Elixir] ++ parts)

        if Code.ensure_loaded?(maybe_without_alias) do
          maybe_without_alias
        else
          :error
        end

      {_as, fqn} ->
        fqn
    end
  end

  defp imported?(env, split, name, arity) do
    mod = Module.concat(split)

    Enum.any?(env.functions, fn {imported_mod, funs} ->
      mod == imported_mod &&
        Enum.any?(funs, fn {fun_name, fun_arity} ->
          fun_name == name and fun_arity == arity
        end)
    end)
  end
end
