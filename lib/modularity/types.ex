defmodule Bonfire.Common.Types do

  def object_type(%{__struct__: schema}), do: object_type(schema)
  def object_type(%{__typename: type}), do: object_type(type) # for graphql queries
  def object_type(%{table_id: type}), do: object_type(type) # for schema-less queries


  # TODO: make config-driven
  def object_type(type) when type in [ValueFlows.EconomicEvent, "EconomicEvent", "2CTVA10BSERVEDF10WS0FVA1VE"], do: ValueFlows.EconomicEvent
  def object_type(type) when type in [ValueFlows.EconomicResource, "EconomicResource"], do: ValueFlows.EconomicResource
  def object_type(type) when type in [ValueFlows.Planning.Intent, "Intent", "1NTENTC0V1DBEAN0FFER0RNEED"], do: ValueFlows.Planning.Intent
  def object_type(type) when type in [ValueFlows.Process, "Process"], do: ValueFlows.Process
  def object_type(type) do
    type
  end

end
