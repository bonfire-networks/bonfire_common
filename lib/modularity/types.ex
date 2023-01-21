defmodule Bonfire.Common.Types do
  use Bonfire.Common.Utils
  use Untangle
  alias Pointers.Pointer
  alias Bonfire.Common.Cache

  @decorate time()
  def object_type(object)

  def object_type(%Ecto.Association.NotLoaded{}) do
    error("cannot detect the type on an association that wasn't preloaded")
    nil
  end

  # for schema-less queries
  def object_type(%{table_id: type}), do: object_type(type)
  # for graphql queries
  def object_type(%{__typename: type}) when type != Pointer,
    do: object_type(type)

  # for AP objects
  def object_type(%{pointer_id: type}), do: object_type(type)
  # for search results
  def object_type(%{index_type: type}), do: object_type(maybe_to_atom(type))
  # for activities
  def object_type(%{object: object}), do: object_type(object)

  def object_type(%{__struct__: schema}) when schema != Pointer,
    do: object_type(schema)

  def object_type({:ok, thing}), do: object_type(thing)

  def object_type(%{display_username: display_username}),
    do: object_type(display_username)

  def object_type("@" <> _), do: Bonfire.Data.Identity.User
  def object_type("%40" <> _), do: Bonfire.Data.Identity.User
  def object_type("+" <> _), do: Bonfire.Classify.Category

  # TODO: make config-driven or auto-generate by code (eg. TypeService?)

  # Pointables
  def object_type(type)
      when type in [
             Bonfire.Data.Identity.User,
             "5EVSER1S0STENS1B1YHVMAN01D",
             "User",
             "Users",
             "Person",
             "Organization",
             :user,
             :users
           ],
      do: Bonfire.Data.Identity.User

  def object_type(type)
      when type in [
             Bonfire.Data.Social.Post,
             "30NF1REP0STTAB1ENVMBER0NEE",
             "Posts",
             "Post",
             :post,
             :posts
           ],
      do: Bonfire.Data.Social.Post

  def object_type(type)
      when type in [
             Bonfire.Classify.Category,
             "Category",
             "Categories",
             "Topic",
             "Topics",
             :Category,
             :Topic
           ],
      do: Bonfire.Classify.Category

  # Edges / verbs
  def object_type(type)
      when type in [
             Bonfire.Data.Social.Follow,
             "70110WTHE1EADER1EADER1EADE",
             "Follow",
             "Follows",
             :follow
           ],
      do: Bonfire.Data.Social.Follow

  def object_type(type)
      when type in [
             Bonfire.Data.Social.Like,
             "11KES11KET0BE11KEDY0VKN0WS",
             "Like",
             "Likes",
             :like
           ],
      do: Bonfire.Data.Social.Like

  def object_type(type)
      when type in [
             Bonfire.Data.Social.Boost,
             "300STANN0VNCERESHARESH0VTS",
             "Boost",
             "Boosts",
             :boost
           ],
      do: Bonfire.Data.Social.Boost

  # VF
  def object_type(type)
      when type in [
             ValueFlows.EconomicEvent,
             "EconomicEvent",
             "EconomicEvents",
             "2CTVA10BSERVEDF10WS0FVA1VE"
           ],
      do: ValueFlows.EconomicEvent

  def object_type(type)
      when type in [ValueFlows.EconomicResource, "EconomicResource"],
      do: ValueFlows.EconomicResource

  def object_type(type)
      when type in [
             ValueFlows.Planning.Intent,
             "Intent",
             "Intents",
             "ValueFlows.Planning.Offer",
             "ValueFlows.Planning.Need",
             "1NTENTC0V1DBEAN0FFER0RNEED"
           ],
      do: ValueFlows.Planning.Intent

  def object_type(type)
      when type in [ValueFlows.Process, "Process", "4AYF0R1NPVTST0BEC0ME0VTPVT"],
      do: ValueFlows.Process

  def object_type(id) when is_binary(id) do
    with {:ok, schema} <- Pointers.Tables.schema(id) do
      schema
    else
      _ ->
        Cache.maybe_apply_cached(&object_type_from_db/1, [id])
    end
  end

  def object_type(type) when is_atom(type) and not is_nil(type) do
    debug("atom might be a schema type: #{inspect(type)}")
    type
  end

  def object_type(type) do
    error("no pattern matched for #{inspect(type)}")
    nil
  end

  defp object_type_from_db(id) do
    debug(
      id,
      "This isn't the table_id of a known Pointers.Table schema, querying it to check if it's a Pointable"
    )

    case Bonfire.Common.Pointers.one(id, skip_boundary_check: true) do
      {:ok, %{table_id: "601NTERTAB1EF0RA11TAB1ES00"}} ->
        debug("This is the ID of an unknown Pointable")
        nil

      {:ok, %{table_id: table_id}} ->
        object_type(table_id)

      _ ->
        nil
    end
  end

  @decorate time()
  def object_type_display(object_type)
      when is_atom(object_type) and not is_nil(object_type) do
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
    Bonfire.Common.SchemaModule.modules()
    |> Enum.filter(&Bonfire.Common.Utils.defines_struct?/1)
    |> Enum.flat_map(fn t ->
      t =
        t
        |> module_to_human_readable()
        |> sanitise_name()

      if t,
        do: [t, "Delete this #{t}"],
        else: []
    end)
    |> filter_empty([])

    # |> IO.inspect(label: "Making all object types localisable")
  end

  def table_types(types) when is_list(types),
    do: Enum.map(types, &table_type/1) |> Utils.filter_empty([])

  def table_types(type),
    do: table_types(List.wrap(type))

  def table_type(type) when is_atom(type) and not is_nil(type), do: table_id(type)
  def table_type(%{table_id: table_id}) when is_binary(table_id), do: ulid(table_id)
  def table_type(type) when is_map(type), do: object_type(type) |> table_id()

  def table_type(type) when is_binary(type),
    do: String.capitalize(type) |> object_type() |> table_id

  def table_type(_), do: nil

  def table_id(schema) when is_atom(schema) and not is_nil(schema) do
    if Code.ensure_loaded?(schema), do: schema.__pointers__(:table_id)
  end

  def table_id(_), do: nil

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
