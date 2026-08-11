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

  @doc """
  Schemas named by context or query modules via their `schema_module/0` callback, which do not declare this behaviour themselves.

  Most schemas are plain Ecto modules in `bonfire_data_*`: it is their context module (`Bonfire.Posts`, `Bonfire.Me.Users`) that declares the relationship, so `modules/0` alone reports a handful where dozens exist.
  """
  @spec modules_inferred() :: [atom]
  def modules_inferred() do
    alias Bonfire.Common.ExtensionBehaviour

    (ExtensionBehaviour.modules_pointed_at(Bonfire.Common.ContextModule, :schema_module) ++
       ExtensionBehaviour.modules_pointed_at(Bonfire.Common.QueryModule, :schema_module))
    |> Enum.uniq()
  end

  @doc """
  Every schema this app knows about: those declaring `SchemaModule`, plus those inferred from the other two behaviours.

  Prefer this over `modules/0` when you want coverage rather than only modules that opted in.
  """
  @spec modules_all() :: [atom]
  def modules_all(), do: Enum.uniq(modules() ++ modules_inferred())
end
