defmodule Bonfire.Common.AntiSpam do
  @moduledoc """
  Module to load the service adapter defined inside the configuration.

  See `Bonfire.Common.AntiSpam.Provider`.
  """

  @doc """
  Returns the appropriate service adapter.

  According to the config behind
    `config :mobilizon, Bonfire.Common.AntiSpam,
       service: Bonfire.Common.AntiSpam.Module`
  """
  @spec service :: module
  def service,
    do: Bonfire.Common.Config.get([__MODULE__, :service], Bonfire.Common.AntiSpam.Akismet)
end
