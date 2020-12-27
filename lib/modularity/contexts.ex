# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Contexts do
  @doc "Helpers for referring to hypothetical functions in other context modules"

  alias Bonfire.Common.Utils

  require Logger

  def run_context_function(
        object,
        fun,
        args \\ [],
        fallback_fun \\ &run_context_function_error/2
      )

  def run_context_function(object_schema_or_context, fun, args, fallback_fun)
      when is_atom(object_schema_or_context) and is_atom(fun) and is_list(args) and
             is_function(fallback_fun) do
    if Utils.module_exists?(object_schema_or_context) do
      object_context_module =
        if Kernel.function_exported?(object_schema_or_context, :context_module, 0) do
          apply(object_schema_or_context, :context_module, [])
        else
          # fallback to directly using the module provided
          object_schema_or_context
        end

      arity = length(args)

      if Utils.module_exists?(object_context_module) do
        if Kernel.function_exported?(object_context_module, fun, arity) do
          # IO.inspect(function_exists_in: object_context_module)

          try do
            apply(object_context_module, fun, args)
          rescue
            e in FunctionClauseError ->
              fallback_fun.(
                "#{Exception.format_banner(:error, e)}",
                args
              )
          end
        else
          fallback_fun.(
            "No function defined at #{object_context_module}.#{fun}/#{arity}",
            args
          )
        end
      else
        fallback_fun.(
          "No such module (#{object_context_module}) could be loaded.",
          args
        )
      end
    else
      fallback_fun.(
        "No such module (#{object_schema_or_context}) could be loaded.",
        args
      )
    end
  end

  def run_context_function(
        %{__struct__: object_schema_or_context} = _object,
        fun,
        args,
        fallback_fun
      ) do
    run_context_function(object_schema_or_context, fun, args, fallback_fun)
  end

  def run_context_function(object_schema_or_context, fun, args, fallback_fun)
      when not is_list(args) do
    run_context_function(object_schema_or_context, fun, [args], fallback_fun)
  end

  def run_context_function_error(error, args) do
    Logger.error("Error running context function: #{error}")
    IO.inspect(run_context_function: args)

    {:error, error}
  end
end
