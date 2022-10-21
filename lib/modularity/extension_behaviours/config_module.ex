# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ConfigModule do
  @moduledoc """
  A Global cache of known config modules to be queried by associated schema, or vice versa.

  Use of the ConfigModule Service requires:

  1. Exporting `config_module/0` in relevant modules, returning a Module or otp_app atom
  2. To populate `:bonfire, :extensions_grouped, Bonfire.Common.ConfigModule` in config the list of OTP applications where config_modules are declared.
  3. Start the `Bonfire.Common.ConfigModule` application before querying.
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

  @doc "Declares a config module"
  @callback config_module() :: any

  @doc "Set runtime config"
  @callback config() :: any

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end
end
