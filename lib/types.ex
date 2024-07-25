defmodule Bonfire.Common.Types do
  @moduledoc "Helpers for handling the type of objects (structs and more)"
  use Untangle
  import Bonfire.Common.Extend
  require Bonfire.Common.Localise.Gettext
  import Bonfire.Common.Localise.Gettext.Helpers

  alias Needle.Pointer
  alias Bonfire.Common.Cache
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Text

  @doc """
  Takes an object and returns its data type as a module name or atom.

  ## Examples

      iex> typeof(%{__struct__: Ecto.Schema})
      Ecto.Schema

      iex> typeof(%{__context__: nil, __changed__: nil})
      :assigns

      iex> typeof(nil)
      :empty

      iex> typeof(%Ecto.Changeset{})
      Ecto.Changeset

      iex> typeof([1, 2])
      List

      iex> typeof([])
      :empty

      iex> typeof("string")
      String

      iex> typeof(:atom)
      Atom

      iex> typeof(123)
      Integer

      iex> typeof(%{id: 1})
      Map

      iex> typeof(%{})
      :empty

      iex> typeof(3.14)
      Float

      iex> typeof({:ok, 42})
      Tuple

      iex> typeof(fn -> :ok end)
      Function

      iex> typeof(self())
      Process

      iex> typeof(Port.open({:spawn, "cat"}, [:binary]))
      Port

      iex> typeof(make_ref())
      :reference

      iex> typeof(%{__struct__: Bonfire.Classify.Category})
      Bonfire.Classify.Category
  """
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
      object_type(string) || Needle.ULID
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

  @doc """
  Takes an object or list of objects and returns the ULID (Universally Unique Lexicographically Sortable Identifier) ID(s) if present in the object.

  ## Examples

      iex> ulid(%{pointer_id: "01J3MNBPD0VX96MFY9B15BCHYP"})
      "01J3MNBPD0VX96MFY9B15BCHYP"

      iex> ulid(%{pointer: %{id: "01J3MNBPD0VX96MFY9B15BCHYP"}})
      "01J3MNBPD0VX96MFY9B15BCHYP"

      iex> ulid(%{id: "01J3MNBPD0VX96MFY9B15BCHYP"})
      "01J3MNBPD0VX96MFY9B15BCHYP"
      
      iex> ulid("01J3MNBPD0VX96MFY9B15BCHYP")
      "01J3MNBPD0VX96MFY9B15BCHYP"

      iex> ulid(["01J3MNBPD0VX96MFY9B15BCHYP", "01J3MQ2Q4RVB1WTE3KT1D8ZNX1"])
      ["01J3MNBPD0VX96MFY9B15BCHYP", "01J3MQ2Q4RVB1WTE3KT1D8ZNX1"]

      iex> ulid("invalid_id")
      nil
  """
  def ulid(%{pointer_id: id}) when is_binary(id), do: ulid(id)
  def ulid(%{pointer: %{id: id}}) when is_binary(id), do: ulid(id)

  def ulid(input) when is_binary(input) do
    # ulid is always 26 chars
    id = String.slice(input, 0, 26)

    if is_ulid?(id) do
      id
    else
      e = "Expected a ULID ID (or an object with one)"

      # throw {:error, e}
      warn(input, e)
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
        # e = "Expected a ULID ID (or an object with one)"
        # throw {:error, e}
        # debug(id, e)
        # not showing the error because `Enums.id` already outputs one ^
        nil
    end
  end

  def ulids(objects), do: ulid(objects) |> List.wrap()

  def ulids_or(objects, fallback_or_fun) when is_list(objects) do
    Enum.flat_map(objects, &ulids_or(&1, fallback_or_fun))
  end

  def ulids_or(object, fun) when is_function(fun) do
    List.wrap(ulid(object) || fun.(object))
  end

  def ulids_or(object, fallback) do
    List.wrap(ulid(object) || fallback)
  end

  @doc """
  Takes an object and returns the ULID (Universally Unique Lexicographically Sortable Identifier) ID if present in the object. Throws an error if a ULID ID is not present.

  ## Examples

      iex> ulid!(%{pointer_id: "01J3MNBPD0VX96MFY9B15BCHYP"})
      "01J3MNBPD0VX96MFY9B15BCHYP"

      iex> ulid!("invalid_id")
      ** (RuntimeError) Expected an object or ID (ULID)
  """
  def ulid!(object) do
    case ulid(object) do
      id when is_binary(id) ->
        id

      _ ->
        error(object, "Expected an object or ID (ULID), but got")
        raise "Expected an object or ID (ULID)"
    end
  end

  @doc """
  Takes a value and returns true if it's a number or can be converted to a float.

  ## Examples
    iex> is_numeric(123)
    true

    iex> is_numeric("123.45")
    true

    iex> is_numeric("abc")
    false
  """
  def is_numeric(num) when is_integer(num) or is_float(num), do: true

  def is_numeric(str) when is_binary(str) do
    case Float.parse(str) do
      {_num, ""} -> true
      _ -> false
    end
  end

  def is_numeric(_), do: false

  @doc """
  Converts a value to a floating-point number if possible. If the value cannot be converted to a float, it returns a fallback value (which defaults to 0 if not provided).

  ## Examples
    iex> maybe_to_float(123)
    123

    iex> maybe_to_float("123.45")
    123.45

    iex> maybe_to_float("abc", 0.0)
    0.0
  """
  def maybe_to_float(val, fallback \\ 0)
  def maybe_to_float(num, _fallback) when is_integer(num) or is_float(num), do: num

  def maybe_to_float(atom, fallback) when is_atom(atom),
    do: Atom.to_string(atom) |> maybe_to_float(fallback)

  def maybe_to_float(str, fallback) do
    case Float.parse(str) do
      {num, ""} ->
        num

      {num, extra} ->
        warn(extra, "Do not convert value because Float.parse found extra data in the input")
        fallback

      _ ->
        fallback
    end
  end

  @doc """
  Converts a value to an integer if possible. If the value is not an integer, it attempts to convert it to a float and then rounds it to the nearest integer. Otherwise it returns a fallback value (which defaults to 0 if not provided).

  ## Examples
    iex> maybe_to_integer(123.45)
    123

    iex> maybe_to_integer("123")
    123

    iex> maybe_to_integer("abc", 0)
    0
  """
  def maybe_to_integer(val, fallback \\ 0)
  def maybe_to_integer(val, _fallback) when is_integer(val), do: val
  def maybe_to_integer(val, _fallback) when is_float(val), do: round(val)

  def maybe_to_integer(val, fallback) do
    case maybe_to_float(val, nil) do
      nil ->
        fallback

      float ->
        round(float)
    end
  end

  @doc """
  Takes a string and returns true if it is a valid ULID (Universally Unique Lexicographically Sortable Identifier).

  ## Examples
    iex> is_ulid?("01J3MQ2Q4RVB1WTE3KT1D8ZNX1")
    true

    iex> is_ulid?("invalid_ulid")
    false
  """
  def is_ulid?(str) when is_binary(str) and byte_size(str) == 26 do
    with :error <- Needle.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid?(_), do: false

  @doc """
  Takes a string and returns true if it is a valid UUID (Universally Unique Identifier).

  ## Examples
    iex> is_uuid?("550e8400-e29b-41d4-a716-446655440000")
    true

    iex> is_uuid?("invalid_uuid")
    false
  """
  def is_uuid?(str) do
    with true <- is_binary(str) and byte_size(str) == 36,
         {:ok, _} <- Ecto.UUID.cast(str) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Takes a string and returns an atom if it can be converted to one, else returns the input itself.

  ## Examples
    iex> maybe_to_atom("atom_name")
    :atom_name

    iex> maybe_to_atom("def_non_existing_atom")
    "def_non_existing_atom"
  """
  def maybe_to_atom(str) when is_binary(str) do
    maybe_to_atom!(str) || str
  end

  def maybe_to_atom(other), do: other

  @doc """
  Takes a string or an atom and returns an atom if it is one or can be converted to one, else returns nil.

  ## Examples
    iex> maybe_to_atom!("atom_name")
    :atom_name

    iex> maybe_to_atom!("def_non_existing_atom")
    nil
  """
  def maybe_to_atom!("false"), do: false
  def maybe_to_atom!("nil"), do: nil
  def maybe_to_atom!(""), do: nil

  def maybe_to_atom!(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> nil
    end
  end

  def maybe_to_atom!(atom) when is_atom(atom), do: atom
  def maybe_to_atom!(_), do: nil

  @doc """
  Takes a string and returns the corresponding Elixir module if it exists and is not disabled in the app.

  ## Examples
    iex> maybe_to_module("Enum")
    Enum

    iex> maybe_to_module("NonExistentModule")
    nil
  """
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

  @doc """
  Takes a string or atom and attempts to convert it to an atom or module, depending on the flags.

  ## Examples
    iex> maybe_to_atom_or_module(:some_atom, true, true)
    :some_atom

    iex> maybe_to_atom_or_module("Enum", true, true)
    Enum
  """
  def maybe_to_atom_or_module(k, _force, _to_snake) when is_atom(k),
    do: k

  def maybe_to_atom_or_module(k, true = force, true = _to_snake),
    do: maybe_to_module(k, force) || Text.maybe_to_snake(k) |> String.to_atom()

  def maybe_to_atom_or_module(k, _false = force, true = _to_snake),
    do: maybe_to_module(k, force) || maybe_to_snake_atom(k)

  def maybe_to_atom_or_module(k, true = force, _false = _to_snake) when is_binary(k),
    do: maybe_to_module(k, force) || String.to_atom(k)

  def maybe_to_atom_or_module(k, _false = force, _false = _to_snake),
    do: maybe_to_module(k, force) || maybe_to_atom(k)

  @doc """
  Takes a module atom and converts it to a string, or a string and removes the `Elixir.` prefix if it exists.

  ## Examples
    iex> module_to_str(SomeModule)
    "SomeModule"

    iex> module_to_str(Elixir.SomeModule)
    "SomeModule"
  """
  def module_to_str(str) when is_binary(str) do
    case str do
      "Elixir." <> name -> name
      other -> other
    end
  end

  def module_to_str(atom) when is_atom(atom),
    do: maybe_to_string(atom) |> module_to_str()

  @doc """
  Handles multiple cases where the input value is of a different type (atom, list, tuple, etc.) and returns a string representation of it.

  ## Examples
  iex> maybe_to_string(:some_atom)
  "some_atom"

  iex> maybe_to_string([1, 2, 3])
  "[1, 2, 3]"

  iex> maybe_to_string({:a, :tuple})
  "a: tuple"
  """
  def maybe_to_string(atom) when is_atom(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  def maybe_to_string(list) when is_list(list) do
    # IO.inspect(list, label: "list")
    inspect(list)
  end

  def maybe_to_string({key, val}) do
    maybe_to_string(key) <> ": " <> maybe_to_string(val)
  end

  def maybe_to_string(other) do
    to_string(other)
  end

  @doc """
  Takes a module name (as a string or an atom) and converts it to a human-readable string. 

  It removes the `Elixir.` prefix (if it exists) and any other prefixes (e.g., `Bonfire.Common.`) and converts the final part of the module name to a string in title case (e.g., `Types`).

  ## Examples
    iex> module_to_human_readable("Elixir.Bonfire.Common.Types")
    "Types"

    iex> module_to_human_readable(Bonfire.Common.Types)
    "Types"
  """
  def module_to_human_readable(module) do
    module
    |> module_to_str()
    |> String.split(".")
    |> List.last()
    |> Recase.to_title()
  end

  @doc """
  Takes a map or list of maps, and if the value of a key in the map is a ULID, it replaces it with the corresponding Crockford Base32 encoded string.

  ## Examples
    iex> maybe_convert_ulids(%{key: "01FJ4ZZZ8P5RMZMM00XDDDF8"})
    %{key: "01FJ4ZZZ8P5RMZMM00XDDDF8"}

    iex> maybe_convert_ulids([%{key: "01FJ4ZZZ8P5RMZMM00XDDDF8"}])
    [%{key: "01FJ4ZZZ8P5RMZMM00XDDDF8"}]
  """
  def maybe_convert_ulids(list) when is_list(list),
    do: Enum.map(list, &maybe_convert_ulids/1)

  def maybe_convert_ulids(%{} = map) do
    map |> Enum.map(&maybe_convert_ulids/1) |> Map.new()
  end

  def maybe_convert_ulids({key, val}) when byte_size(val) == 16 do
    with {:ok, ulid} <- Needle.ULID.load(val) do
      {key, ulid}
    else
      _ ->
        {key, val}
    end
  end

  def maybe_convert_ulids({:ok, val}), do: {:ok, maybe_convert_ulids(val)}
  def maybe_convert_ulids(val), do: val

  @doc """
  Takes a string as input, converts it to snake_case, and converts it to an atom if such an atom exists, otherwise returns nil.

  ## Examples
    iex> maybe_to_snake_atom("SomeString")
    :some_string

    iex> maybe_to_snake_atom("DefNonExistingAtom")
    nil
  """
  def maybe_to_snake_atom(string), do: maybe_to_atom!(Text.maybe_to_snake(string))

  @doc """
  Takes an object or module name and checks if it defines a struct.

  ## Examples
    iex> defines_struct?(Needle.Pointer)
    true

    iex> defines_struct?(%{__struct__: Bonfire.Common})
    true

    iex> defines_struct?(%{some_key: "some_value"})
    false
  """
  def defines_struct?(module) when is_atom(module) do
    function_exported?(module, :__struct__, 0)
  end

  def defines_struct?(%{__struct__: module}) when is_atom(module) do
    true
  end

  def defines_struct?(_) do
    false
  end

  @doc """
  Takes an object, module name, or string, and returns the type of the object. 

  The function uses various patterns to match different object types (such as associations, Pointables, edges/verbs, etc.). If none of the patterns match, the function returns nil.

  ## Examples
    iex> object_type(%Ecto.Association.NotLoaded{})
    nil

    iex> object_type(%{table_id: "601NTERTAB1EF0RA11TAB1ES00"})
    Needle.Table

    iex> object_type(%{pointer_id: "User"})
    Bonfire.Data.Identity.User

    iex> object_type("User")
    Bonfire.Data.Identity.User

    iex> object_type(:some_atom)
    :some_atom
  """
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
  def object_type(%{"index_type" => type}), do: object_type(maybe_to_atom(type))
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
  def object_type("&" <> _), do: :group

  # TODO: make config-driven or auto-generate by code (eg. TypeService?)

  # Pointables
  def object_type(type)
      when type in [
             Bonfire.Data.Identity.User,
             "Bonfire.Data.Identity.User",
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
             "Group",
             "Groups",
             :Category,
             :Group,
             :group,
             "2AGSCANBECATEG0RY0RHASHTAG"
           ],
      do: :group

  def object_type(type)
      when type in [
             #  Bonfire.Classify.Category,
             #  "Category",
             #  "Categories",
             "Topic",
             "Topics",
             #  :Category,
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

  def object_type(type)
      when type in [
             Bonfire.Files.Media,
             "30NF1REF11ESC0NTENT1SGREAT",
             "Media",
             :media
           ],
      do: Bonfire.Files.Media

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
    with {:ok, schema} <- Needle.Tables.schema(id) do
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
    # warn(type, "no pattern matched")
    # typeof(type)
    nil
  end

  defp object_type_from_db(id) do
    debug(
      id,
      "This isn't the table_id of a known Needle.Table schema, querying it to check if it's a Pointable"
    )

    case Bonfire.Common.Needles.one(id, skip_boundary_check: true) do
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

  @doc """
  Outputs a human-readable representation of an object type.

  ## Examples
    iex> object_type_display(:user)
    "user"

    iex> object_type_display(%Bonfire.Data.Social.APActivity{})
    "apactivity"
  """
  # @decorate time()
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
  Outputs the names of all object types for the purpose of adding to the localisation strings (as long as the output is piped through to `Bonfire.Common.Localise.Gettext.localise_strings/1` at compile time)

    > all_object_type_names()
    ["User", "Delete this User", "Post", "Delete this Post", ...]
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

  @doc """
  Given a list of schema types, returns a list of their respective table types. Filters out any empty values. 

    iex> table_types([%Needle.Pointer{table_id: "30NF1REAPACTTAB1ENVMBER0NE"}, %Bonfire.Data.Social.APActivity{}])
    ["30NF1REAPACTTAB1ENVMBER0NE"]

    Given a single schema type, it returns its respective table type.

    iex> table_types(Bonfire.Data.Social.APActivity)
    ["30NF1REAPACTTAB1ENVMBER0NE"]
  """
  def table_types(types) when is_list(types),
    do: Enum.map(types, &table_type/1) |> Enums.filter_empty([]) |> Enum.dedup()

  def table_types(type),
    do: table_types(List.wrap(type))

  @doc """
  Given an object or module name, returns its respective table table ID (i.e. Pointable ULID).

  ## Examples
    iex> table_type(%Bonfire.Data.Social.APActivity{})
    "30NF1REAPACTTAB1ENVMBER0NE"
    
    iex> table_type(%Needle.Pointer{table_id: "30NF1REAPACTTAB1ENVMBER0NE"})
    "30NF1REAPACTTAB1ENVMBER0NE"

    iex> table_type(Bonfire.Data.Social.APActivity)
    "30NF1REAPACTTAB1ENVMBER0NE"
  """
  def table_type(type) when is_atom(type) and not is_nil(type) do
    table_id(type) ||
      type
      |> object_type()
      |> table_id()
  end

  def table_type(%{table_id: table_id}) when is_binary(table_id), do: ulid(table_id)
  def table_type(type) when is_map(type), do: object_type(type) |> table_id()

  def table_type(type) when is_binary(type) do
    if is_ulid?(type) do
      type
    else
      String.capitalize(type)
    end
    |> object_type()
    |> table_id()
  end

  def table_type(_), do: nil

  @doc """
  Given a schema module, returns its table ID (i.e. Pointable ULID).

  ## Examples
    iex> table_id(Bonfire.Data.Social.APActivity)
    "30NF1REAPACTTAB1ENVMBER0NE"
  """
  def table_id(schema) when is_atom(schema) and not is_nil(schema) do
    if Extend.module_exists?(schema), do: schema.__pointers__(:table_id)
  end

  def table_id(_), do: nil

  @doc """
  Used for mapping schema types to user-friendly names. Given a string representing a schema type name, returns a sanitised version of it, or nil for object types (or mixins) that shouldn't be displayed.

  ## Examples
    iex> sanitise_name("Apactivity")
    "Federated Object"

    iex> sanitise_name("Settings")
    "Setting"

    iex> sanitise_name("Created")
    nil
  """
  def sanitise_name("Replied"), do: "Reply in Thread"
  def sanitise_name("Named"), do: "Name"
  def sanitise_name("Settings"), do: "Setting"
  def sanitise_name("Apactivity"), do: "Federated Object"
  def sanitise_name("Feed Publish"), do: "Activity in Feed"
  def sanitise_name("Acl"), do: "Boundary"
  def sanitise_name("Controlled"), do: "Object Boundary"
  def sanitise_name("Tagged"), do: "Tag"
  def sanitise_name("Files"), do: "File"
  def sanitise_name("Created"), do: nil
  def sanitise_name("File Denied"), do: nil
  def sanitise_name("Accounted"), do: nil
  def sanitise_name("Seen"), do: nil
  def sanitise_name("Self"), do: nil
  def sanitise_name("Peer"), do: nil
  def sanitise_name("Peered"), do: nil
  def sanitise_name("Encircle"), do: nil
  def sanitise_name("Care Closure"), do: nil
  def sanitise_name(type), do: Text.verb_infinitive(type) || type
end

defimpl Jason.Encoder, for: Tuple do
  def encode(data, opts) when is_tuple(data) do
    Jason.Encode.map(Map.new([data]), opts)
  end
end
