# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Contexts do
  @doc "Helpers for referring to hypothetical functions in other context modules"

  alias Bonfire.Common.Utils

  require Logger

  def run_module_function(
    module,
    fun,
    args \\ [],
    fallback_fun \\ &run_context_function_error/2
  )

  def run_module_function(
      module,
      fun,
      args,
      fallback_fun
    )
    when is_atom(module) and is_atom(fun) and is_list(args) and
            is_function(fallback_fun) do

    arity = length(args)

    if Utils.module_exists?(module) do
      if Kernel.function_exported?(module, fun, arity) do
        #IO.inspect(function_exists_in: module)

        try do
          apply(module, fun, args)
        rescue
          e in FunctionClauseError ->
            fallback_fun.(
              "#{Exception.format_banner(:error, e)}",
              args
            )
        end
      else
        fallback_fun.(
          "No function defined at #{module}.#{fun}/#{arity}",
          args
        )
      end
    else
      fallback_fun.(
        "No such module (#{module}) could be loaded.",
        args
      )
    end
  end

    def run_module_function(
      module,
      fun,
      args,
      fallback_fun
    )
    when is_atom(module) and is_atom(fun) and
            is_function(fallback_fun), do: run_module_function(
      module,
      fun,
      [args],
      fallback_fun
    )

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

      run_module_function(
        object_context_module,
        fun,
        args,
        fallback_fun
      )

    else
      fallback_fun.(
        "No such module (#{object_schema_or_context}) could be found.",
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

  def run_context_function_error(error, args, level \\ :error) do
    Logger.log(level, "Bonfire.Contexts: Error running function: #{error} with args: (#{inspect args})")

    {:error, error}
  end
end
