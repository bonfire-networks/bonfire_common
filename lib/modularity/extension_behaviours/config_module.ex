# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ConfigModule do
  @moduledoc """
  A global cache of runtime config modules to be loaded at app startup.
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
