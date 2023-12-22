# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ContextModule do
  @moduledoc """
  Find a context or query module via its schema, backed by a global cache of known modules.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a context module"
  @callback context_module() :: any

  @doc "Points to the related schema module"
  @callback schema_module() :: atom

  @doc "Points to the related queries module"
  @callback query_module() :: atom

  @doc """
  Given an object or schema module name, run a function on the associated context module.
  """
  def maybe_apply(
        object_schema_or_context,
        fun,
        args \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_apply(schema_or_context, fun, args, fallback_fun)
      when is_atom(schema_or_context) and (is_atom(fun) or is_list(fun)) and is_list(args) and
             is_function(fallback_fun) do
    if module_enabled?(schema_or_context) do
      object_context_module = maybe_context_module(schema_or_context)

      Utils.maybe_apply(
        object_context_module,
        fun,
        args,
        fallback_fun
      )
    else
      fallback_fun.(
        "ContextModule: Module could be found: #{schema_or_context}",
        args
      )
    end
  end

  def maybe_apply(
        %Pointers.Pointer{} = object,
        fun,
        args,
        fallback_fun
      ) do
    maybe_apply(Bonfire.Common.Types.object_type(object), fun, args, fallback_fun)
  end

  def maybe_apply(
        %{__struct__: schema} = _object,
        fun,
        args,
        fallback_fun
      ) do
    maybe_apply(schema, fun, args, fallback_fun)
  end

  def maybe_apply(object_schema_or_context, fun, args, fallback_fun)
      when not is_list(args) do
    maybe_apply(object_schema_or_context, fun, [args], fallback_fun)
  end

  def apply_error(error, args) do
    error(
      "Bonfire.Common.ContextModule: Error running function: #{error} with args: (#{inspect(args)})"
    )

    {:error, error}
  end

  @doc "Get a context identified by schema"
  def context_module(query) when is_binary(query) or is_atom(query) do
    case query in modules() do
      true ->
        {:ok, query}

      _ ->
        case linked_schema_modules()[query] ||
               Bonfire.Common.SchemaModule.linked_context_modules()[query] do
          nil -> {:error, :not_found}
          module -> {:ok, module}
        end
    end
  end

  @doc "Look up a context, throw :not_found if not found."
  def context_module!(query), do: Map.get(modules(), query) || throw(:not_found)

  @spec context_modules([binary | atom]) :: [binary]
  @doc "Look up many contexts at once, throw :not_found if any of them are not found"
  def context_modules(modules) do
    Enum.map(modules, &Map.get(modules(), &1))
  end

  def maybe_context_module(query) do
    with {:ok, module} <- context_module(query) do
      module
    else
      _ ->
        Utils.maybe_apply(query, :context_module, [], &context_function_error/2)
    end
  end

  def context_function_error(error, _args) do
    warn(
      error,
      "ContextModule - there's no context module declared for this schema: 1) No function context_module/0 that returns this schema atom. 2)"
    )

    nil
  end

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end

  # TODO: cache the linked modules

  def linked_schema_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules(modules(), :schema_module)
  end

  def linked_query_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules(modules(), :query_module)
  end
end
