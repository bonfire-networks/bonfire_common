defmodule Bonfire.Common.Types do
  use Bonfire.Common.Utils
  alias Pointers.Pointer

  import Untangle

  def object_type(%Ecto.Association.NotLoaded{}) do
    error("Types.object_type: cannot detect the type on an association that wasn't preloaded")
    nil
  end

  def object_type(%{table_id: type}), do: object_type(type) # for schema-less queries
  def object_type(%{__typename: type}) when type !=Pointer, do: object_type(type) # for graphql queries
  def object_type(%{pointer_id: type}), do: object_type(type) # for AP objects
  def object_type(%{index_type: type}), do: object_type(maybe_to_atom(type)) # for search results
  def object_type(%{object: object}), do: object_type(object) # for activities
  def object_type(%{__struct__: schema}) when schema !=Pointer, do: object_type(schema)

  def object_type(%{display_username: display_username}), do: object_type(display_username)
  def object_type("@"<>_), do: Bonfire.Data.Identity.User
  def object_type("%40"<>_), do: Bonfire.Data.Identity.User
  def object_type("+"<>_), do: Bonfire.Classify.Category

  # TODO: make config-driven or auto-generate by code (eg. TypeService?)

  # Pointables
  def object_type(type) when type in [Bonfire.Data.Identity.User, "5EVSER1S0STENS1B1YHVMAN01D", "User", "Person", "Organization"], do: Bonfire.Data.Identity.User
  def object_type(type) when type in [Bonfire.Data.Social.Post, "30NF1REP0STTAB1ENVMBER0NEE", "Post"], do: Bonfire.Data.Social.Post
  def object_type(type) when type in [Bonfire.Classify.Category, "Category", "Topic", :Category, :Topic], do: Bonfire.Classify.Category

  # Edges / verbs
  def object_type(type) when type in [Bonfire.Data.Social.Follow, "70110WTHE1EADER1EADER1EADE", "Follow", :follow], do: Bonfire.Data.Social.Follow
  def object_type(type) when type in [Bonfire.Data.Social.Like, "11KES11KET0BE11KEDY0VKN0WS", "Like", :like], do: Bonfire.Data.Social.Like
  def object_type(type) when type in [Bonfire.Data.Social.Boost, "300STANN0VNCERESHARESH0VTS", "Boost", :boost], do: Bonfire.Data.Social.Boost

  # VF
  def object_type(type) when type in [ValueFlows.EconomicEvent, "EconomicEvent", "2CTVA10BSERVEDF10WS0FVA1VE"], do: ValueFlows.EconomicEvent
  def object_type(type) when type in [ValueFlows.EconomicResource, "EconomicResource"], do: ValueFlows.EconomicResource
  def object_type(type) when type in [ValueFlows.Planning.Intent, "Intent", "ValueFlows.Planning.Offer", "ValueFlows.Planning.Need", "1NTENTC0V1DBEAN0FFER0RNEED"], do: ValueFlows.Planning.Intent
  def object_type(type) when type in [ValueFlows.Process, "Process", "4AYF0R1NPVTST0BEC0ME0VTPVT"], do: ValueFlows.Process


  def object_type(type) when is_binary(type) do
    with {:ok, schema} <- Pointers.Tables.schema(type) do
      schema
    else _ ->
      error("Types.object_type: could not find a Pointers.Table schema for #{inspect type}")
      nil
    end
  end

  def object_type(type) when is_atom(type) and not is_nil(type) do
    debug("Types.object_type: atom might be a schema type: #{inspect type}")
    type
  end

  def object_type(type) do
    error("Types.object_type: no pattern matched for #{inspect type}")
    nil
  end

  def object_type_display(object_type) when is_atom(object_type) and not is_nil(object_type) do
    module_to_human_readable(object_type)
    |> localise_dynamic(__MODULE__)
    |> String.downcase()
  end
  def object_type_display(object) when not is_nil(object) do
    object_type(object)
    |> object_type_display()
  end
  def object_type_display(_) do
    nil
  end

  @doc """
  Outputs the names all object types, for the purpose of adding to the localisation strings, as long as the output is piped through to localise_strings/1 at compile time.
  """
  def all_object_type_names() do
    Bonfire.Common.ContextModules.search_app_modules(Application.fetch_env!(:pointers, :search_path))
    |> Enum.filter(&Bonfire.Common.Utils.defines_struct?/1)
    |> Enum.flat_map(fn t ->
      t = t
      |> Bonfire.Common.Utils.module_to_human_readable()
      |> sanitise_name()

      if t, do: [ t,
        "Delete this #{t}"
      ], else: []
    end)
    |> filter_empty([])
    # |> IO.inspect(label: "Making all object types localisable")
  end

  defp sanitise_name("Replied"), do: "Reply in Thread"
  defp sanitise_name("Named"), do: "Name"
  defp sanitise_name("Settings"), do: "Setting"
  defp sanitise_name("Apactivity"), do: "Federated Object"
  defp sanitise_name("Feed Publish"), do: "Activity in Feed"
  defp sanitise_name("Acl"), do: "Boundary"
  defp sanitise_name("Controlled"), do: "Object Boundary"
  defp sanitise_name("Tagged"), do: "Tag"
  defp sanitise_name("Files"), do: "File"
  defp sanitise_name("Created"), do: nil
  defp sanitise_name("File Denied"), do: nil
  defp sanitise_name("Accounted"), do: nil
  defp sanitise_name("Seen"), do: nil
  defp sanitise_name("Self"), do: nil
  defp sanitise_name("Peer"), do: nil
  defp sanitise_name("Peered"), do: nil
  defp sanitise_name("Encircle"), do: nil
  defp sanitise_name("Care Closure"), do: nil
  defp sanitise_name(type), do: Text.verb_infinitive(type) || type
end
