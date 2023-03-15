defmodule Bonfire.Common.Types do
  use Untangle
  import Bonfire.Common.Extend
  require Bonfire.Common.Localise.Gettext
  import Bonfire.Common.Localise.Gettext.Helpers

  # alias Bonfire.Common.Utils
  alias Pointers.Pointer
  alias Bonfire.Common.Cache
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Text

  def typeof(%{__struct__: exception_struct}) when is_exception(exception_struct),
    do: exception_struct

  def typeof(exception) when is_exception(exception), do: Exception
  def typeof(%{__context__: _, __changed__: _}), do: :assigns
  def typeof(v) when is_nil(v) or v == %{} or v == [] or v == "", do: :empty
  def typeof(%{__struct__: struct}), do: struct
  def typeof(struct) when is_struct(struct), do: object_type(struct) || :struct

  def typeof(list) when is_list(list) do
    if Keyword.keyword?(list), do: Keyword, else: List
  end

  def typeof(string) when is_binary(string) or is_bitstring(string) do
    if is_ulid?(string) do
      object_type(string) || Pointers.ULID
    else
      case maybe_to_module(string) do
        nil -> String
        module -> typeof(module)
      end
    end
  end

  def typeof(atom) when is_atom(atom) do
    if module_exists?(atom) do
      if defines_struct?(atom), do: object_type(atom) || :struct, else: Module
    else
      Atom
    end
  end

  def typeof(number) when is_integer(number), do: Integer
  def typeof(map) when is_map(map), do: object_type(map) || Map
  def typeof(float) when is_float(float), do: Float
  def typeof(tuple) when is_tuple(tuple), do: Tuple
  def typeof(function) when is_function(function), do: Function
  def typeof(pid) when is_pid(pid), do: Process
  def typeof(port) when is_port(port), do: Port
  def typeof(reference) when is_reference(reference), do: :reference
  def typeof(_), do: nil

  def ulid(%{pointer_id: id}) when is_binary(id), do: ulid(id)
  def ulid(%{pointer: %{id: id}}) when is_binary(id), do: ulid(id)

  def ulid(input) when is_binary(input) do
    # ulid is always 26 chars
    id = String.slice(input, 0, 26)

    if is_ulid?(id) do
      id
    else
      e = "Expected a ULID ID (or an object with one), got #{inspect(input)}"

      # throw {:error, e}
      warn(e)
      nil
    end
  end

  def ulid(ids) when is_list(ids),
    do: ids |> List.flatten() |> Enum.map(&ulid/1) |> Enums.filter_empty(nil)

  def ulid(id) do
    case Enums.id(id) do
      id when is_binary(id) or is_list(id) ->
        ulid(id)

      _ ->
        e = "Expected a ULID ID (or an object with one), got #{inspect(id)}"

        # throw {:error, e}
        debug(e)
        nil
    end
  end

  def ulids(objects), do: ulid(objects) |> List.wrap()

  def ulid!(object) do
    case ulid(object) do
      id when is_binary(id) ->
        id

      _ ->
        error(object, "Expected an object or ID (ULID), but got")
        raise "Expected an object or ID (ULID)"
    end
  end

  def is_numeric(str) do
    case Float.parse(str) do
      {_num, ""} -> true
      _ -> false
    end
  end

  def to_number(str) do
    case Float.parse(str) do
      {num, ""} -> num
      _ -> 0
    end
  end

  def is_ulid?(str) when is_binary(str) and byte_size(str) == 26 do
    with :error <- Pointers.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid?(_), do: false

  def is_uuid?(uuid) do
    with true <- is_binary(uuid),
         {:ok, _} <- Ecto.UUID.cast(uuid) do
      true
    else
      _ -> false
    end
  end

  # not sure why but seems needed
  def maybe_to_atom("false"), do: false

  def maybe_to_atom(str) when is_binary(str) do
    maybe_to_atom!(str) || str
  end

  def maybe_to_atom(other), do: other

  def maybe_to_atom!(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> nil
    end
  end

  def maybe_to_atom!(atom) when is_atom(atom), do: atom
  def maybe_to_atom!(_), do: nil

  def maybe_to_module(str, force \\ true)

  def maybe_to_module("Elixir." <> _ = str, force) do
    case maybe_to_atom(str) do
      module_or_atom when is_atom(module_or_atom) and not is_nil(module_or_atom) ->
        maybe_to_module(module_or_atom, force)

      _ ->
        nil
    end
  end

  def maybe_to_module(str, force) when is_binary(str) do
    maybe_to_module("Elixir." <> str, force)
  end

  def maybe_to_module(atom, force) when is_atom(atom) and not is_nil(atom) do
    if force != true or module_enabled?(atom) do
      atom
    else
      nil
    end
  end

  def maybe_to_module(_, _), do: nil

  def module_to_str(str) when is_binary(str) do
    case str do
      "Elixir." <> name -> name
      other -> other
    end
  end

  def module_to_str(atom) when is_atom(atom),
    do: maybe_to_string(atom) |> module_to_str()

  def maybe_to_string(atom) when is_atom(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  def maybe_to_string(list) when is_list(list) do
    # IO.inspect(list, label: "list")
    List.to_string(list)
  end

  def maybe_to_string({key, val}) do
    maybe_to_string(key) <> ":" <> maybe_to_string(val)
  end

  def maybe_to_string(other) do
    to_string(other)
  end

  @decorate time()
  def module_to_human_readable(module) do
    module
    |> module_to_str()
    |> String.split(".")
    |> List.last()
    |> Recase.to_title()
  end

  def maybe_convert_ulids(list) when is_list(list),
    do: Enum.map(list, &maybe_convert_ulids/1)

  def maybe_convert_ulids(%{} = map) do
    map |> Enum.map(&maybe_convert_ulids/1) |> Map.new()
  end

  def maybe_convert_ulids({key, val}) when byte_size(val) == 16 do
    with {:ok, ulid} <- Pointers.ULID.load(val) do
      {key, ulid}
    else
      _ ->
        {key, val}
    end
  end

  def maybe_convert_ulids({:ok, val}), do: {:ok, maybe_convert_ulids(val)}
  def maybe_convert_ulids(val), do: val

  def maybe_to_snake(string), do: Recase.to_snake("#{string}")

  def maybe_to_snake_atom(string), do: maybe_to_atom!(maybe_to_snake(string))

  def maybe_to_integer(val, fallback \\ 0)
  def maybe_to_integer(val, _fallback) when is_integer(val), do: val

  def maybe_to_integer(val, fallback) do
    case Integer.parse(val) do
      {int, _} -> int
      _ -> fallback
    end
  end

  def defines_struct?(module) do
    function_exported?(module, :__struct__, 0)
  end

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

  # for groups/topics
  def object_type(%{__struct__: Bonfire.Classify.Category, type: :group}), do: :group

  def object_type(%{__struct__: schema}) when schema != Pointer,
    do: object_type(schema)

  def object_type({:ok, thing}), do: object_type(thing)

  def object_type(%{display_username: display_username}),
    do: object_type(display_username)

  def object_type("@" <> _), do: Bonfire.Data.Identity.User
  def object_type("%40" <> _), do: Bonfire.Data.Identity.User
  def object_type("+" <> _), do: Bonfire.Classify.Category
  def object_type("&" <> _), do: Bonfire.Classify.Category

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

  def object_type(type)
      when type in [Bonfire.Classify.Category, "Category", "2AGSCANBECATEG0RY0RHASHTAG"],
      do: Bonfire.Classify.Category

  def object_type(id) when is_binary(id) do
    with {:ok, schema} <- Pointers.Tables.schema(id) do
      schema
    else
      _ ->
        Cache.maybe_apply_cached(&object_type_from_db/1, [id])
    end
  end

  def object_type(type) when is_atom(type) and not is_nil(type) do
    debug(type, "atom might be a schema type")
    type
  end

  def object_type(%{activity: %{id: _} = activity}) do
    object_type(activity)
  end

  def object_type(%{object: %{id: _} = object}) do
    object_type(object)
  end

  def object_type(type) do
    warn(type, "no pattern matched")
    nil
  end

  defp object_type_from_db(id) do
    debug(
      id,
      "This isn't the table_id of a known Pointers.Table schema, querying it to check if it's a Pointable"
    )

    case Bonfire.Common.Pointers.one(id, skip_boundary_check: true) do
      {:ok, %{table_id: "601NTERTAB1EF0RA11TAB1ES00"}} ->
        info("This is the ID of an unknown Pointable")
        nil

      {:ok, %{table_id: table_id}} ->
        object_type(table_id)

      _ ->
        info("This is not the ID of a known Pointer")
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
    typeof(object)
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
    |> Enum.filter(&defines_struct?/1)
    |> Enum.flat_map(fn t ->
      t =
        t
        |> module_to_human_readable()
        |> sanitise_name()

      if t,
        do: [t, "Delete this #{t}"],
        else: []
    end)
    |> Enums.filter_empty([])

    # |> IO.inspect(label: "Making all object types localisable")
  end

  def table_types(types) when is_list(types),
    do: Enum.map(types, &table_type/1) |> Enums.filter_empty([])

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
