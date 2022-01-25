defmodule Bonfire.Common.Types do
  alias Bonfire.Common.Utils
  alias Pointers.Pointer

  require Logger

  def object_type(%Ecto.Association.NotLoaded{}) do
    Logger.error("Types.object_type: cannot detect the type on an association that wasn't preloaded")
    nil
  end

  def object_type(%{table_id: type}), do: object_type(type) # for schema-less queries
  def object_type(%{__typename: type}) when type !=Pointer, do: object_type(type) # for graphql queries
  def object_type(%{pointer_id: type}), do: object_type(type) # for AP objects
  def object_type(%{index_type: type}), do: object_type(Utils.maybe_str_to_atom(type)) # for search results
  def object_type(%{object: object}), do: object_type(object) # for activities
  def object_type(%{__struct__: schema}) when schema !=Pointer, do: object_type(schema)

  def object_type(%{display_username: display_username}), do: object_type(display_username)
  def object_type("@"<>_), do: Bonfire.Data.Identity.User
  def object_type("%40"<>_), do: Bonfire.Data.Identity.User

  # TODO: make config-driven or auto-generate by code (eg. TypeService?)

  def object_type(type) when type in [Bonfire.Data.Identity.User, "5EVSER1S0STENS1B1YHVMAN01D", "User", "Person", "Organization"], do: Bonfire.Data.Identity.User
  def object_type(type) when type in [Bonfire.Data.Social.Post, "30NF1REP0STTAB1ENVMBER0NEE", "Post"], do: Bonfire.Data.Social.Post
  def object_type(type) when type in [Bonfire.Classify.Category, "Category", "Topic", :Category, :Topic], do: Bonfire.Classify.Category

  # TODO: autogenerate from config/pointer tables/API schema, etc?
  def object_type(type) when type in [ValueFlows.EconomicEvent, "EconomicEvent", "2CTVA10BSERVEDF10WS0FVA1VE"], do: ValueFlows.EconomicEvent
  def object_type(type) when type in [ValueFlows.EconomicResource, "EconomicResource"], do: ValueFlows.EconomicResource
  def object_type(type) when type in [ValueFlows.Planning.Intent, "Intent", "ValueFlows.Planning.Offer", "ValueFlows.Planning.Need", "1NTENTC0V1DBEAN0FFER0RNEED"], do: ValueFlows.Planning.Intent
  def object_type(type) when type in [ValueFlows.Process, "Process"], do: ValueFlows.Process


  def object_type(type) when is_binary(type) do
    with {:ok, schema} <- Pointers.Tables.schema(type) do
      schema
    else _ ->
      Logger.error("Types.object_type: could not find a Pointers.Table schema for #{inspect type}")
      nil
    end
  end

  def object_type(type) when is_atom(type) and not is_nil(type) do
    Logger.debug("Types.object_type: atom might be a schema type: #{inspect type}")
    type
  end

  def object_type(type) do
    Logger.error("Types.object_type: no pattern matched for #{inspect type}")
    nil
  end

end
