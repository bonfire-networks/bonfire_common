defmodule Bonfire.Common.SchemaModule do
  @moduledoc """
  Find a context or query module via its schema, backed by a global cache of known schema modules to be queried by their schema, or vice versa (eg. via ContextModule).
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a schema module"
  @callback schema_module() :: any

  @doc "Points to the related query module"
  @callback query_module() :: atom

  @doc "Points to the related context module"
  @callback context_module() :: atom

  @optional_callbacks schema_module: 0, query_module: 0, context_module: 0

  def app_modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_app_modules(__MODULE__)
  end

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end

  def linked_query_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules_cached(modules(), :query_module)
  end

  def linked_context_modules() do
    Bonfire.Common.ExtensionBehaviour.apply_modules_cached(modules(), :context_module)
  end
end
