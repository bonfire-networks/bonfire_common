defmodule Bonfire.Common.SchemaModule do
  @moduledoc """
  Properly schema some data using the appropriate module depending on its schema.

  Back by a global cache of known schema_modules to be queried by their schema, or vice versa.

  Use of the SchemaModule Service requires:

  1. Exporting `schema_module/0` in relevant modules (in schemas pointing to schema modules and/or in schema modules pointing to schemas), returning a Module atom
  2. To populate `:pointers, :search_path` in config the list of OTP applications where schema_modules are declared.
  3. Start the `Bonfire.Common.SchemaModule` application before schemaing.
  4. OTP 21.2 or greater, though we recommend using the most recent
     release available.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a schema module"
  @callback schema_module() :: any

  @doc "Points to the related query module"
  @callback query_module() :: atom

  @doc "Points to the related context module"
  @callback context_module() :: atom

  def app_modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_app_modules(__MODULE__)
  end

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end

  def linked_query_modules() do
    Bonfire.Common.ExtensionBehaviour.linked_modules(modules(), :query_module)
  end

  def linked_context_modules() do
    Bonfire.Common.ExtensionBehaviour.linked_modules(modules(), :context_module)
  end
end
