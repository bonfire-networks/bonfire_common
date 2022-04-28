defmodule Bonfire.Common.Utils do
  use Arrows
  import Bonfire.Common.URIs
  import Bonfire.Common.Extend
  require Bonfire.Web.Gettext
  import Bonfire.Web.Gettext.Helpers
  import Where
  require Logger
  import Phoenix.LiveView
  alias Bonfire.Common.Text
  alias Bonfire.Common.Config
  alias Ecto.Changeset

  defmacro __using__(opts) do
    quote do
      alias Bonfire.Common
      alias Common.Utils
      alias Common.Config
      alias Common.Extend

      require Utils
      import Utils, unquote(opts) # can import specific functions with `only` or `except`

      import Extend

      import Where
      use Arrows

      # localisation
      require Bonfire.Web.Gettext
      import Bonfire.Web.Gettext.Helpers
    end
  end

  def strlen(x) when is_nil(x), do: 0
  def strlen(%{} = obj) when obj == %{}, do: 0
  def strlen(%{}), do: 1
  def strlen(x) when is_binary(x), do: String.length(x)
  def strlen(x) when is_list(x), do: length(x)
  def strlen(x) when x > 0, do: 1
  # let's just say that 0 is nothing
  def strlen(x) when x == 0, do: 0

  @doc "Returns a value, or a fallback if nil/false"
  def e(key, fallback) do
    key || fallback
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e({:ok, object}, key, fallback), do: e(object, key, fallback)

  # def e(object, :current_user = key, fallback) do #temporary
  #       debug(key: key)
  #       debug(e_object: object)

  #       case object do
  #     %{__context__: context} ->
  #       debug(key: key)
  #       debug(e_context: context)
  #       # try searching in Surface's context (when object is assigns), if present
  #       map_get(object, key, nil) || map_get(context, key, nil) || fallback

  #     map when is_map(map) ->
  #       # attempt using key as atom or string, fallback if doesn't exist or is nil
  #       map_get(map, key, nil) || fallback

  #     list when is_list(list) and length(list)==1 ->
  #       # if object is a list with 1 element, try with that
  #       e(List.first(list), key, nil) || fallback

  #     _ -> fallback
  #   end
  # end

  def e(object, key, fallback) do
    case object do
      %{__context__: context} ->
        # try searching in Surface's context (when object is assigns), if present
        case map_get(object, key, nil) do
          result when is_nil(result) or result==fallback -> map_get(context, key, fallback)
          result -> result
        end

      map when is_map(map) ->
        # attempt using key as atom or string, fallback if doesn't exist or is nil
        map_get(map, key, nil) || fallback

      list when is_list(list) and length(list)==1 ->

        if not Keyword.keyword?(list) do
          # if object is a list with 1 element, look inside
          e(List.first(list), key, nil) || fallback
        else
          list |> Map.new() |> e(key, fallback)
        end

      list when is_list(list) ->

        if not Keyword.keyword?(list) do
          list |> Enum.reject(&is_nil/1) |> Enum.map(&(e(&1, key, fallback)))
        else
          list |> Map.new() |> e(key, fallback)
        end

      _ -> fallback
    end
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def e(object, key1, key2, fallback) do
    e(object, key1, %{})
    |> e(key2, fallback)
  end
  def e(object, key1, key2, key3, fallback) do
    e(object, key1, key2, %{})
    |> e(key3, fallback)
  end
  def e(object, key1, key2, key3, key4, fallback) do
    e(object, key1, key2, key3, %{})
    |> e(key4, fallback)
  end
  def e(object, key1, key2, key3, key4, key5, fallback) do
    e(object, key1, key2, key3, key4, %{})
    |> e(key5, fallback)
  end
  def e(object, key1, key2, key3, key4, key5, key6, fallback) do
    e(object, key1, key2, key3, key4, key5, %{})
    |> e(key6, fallback)
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

  def is_ulid?(str) when is_binary(str) and byte_size(str)==26 do
    with :error <- Pointers.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid?(_), do: false

  def ulid(%{id: id}) when is_binary(id), do: ulid(id)
  def ulid(%Changeset{}=cs), do: ulid(Changeset.get_field(cs, :id))
  def ulid(%{pointer_id: id}) when is_binary(id), do: ulid(id)
  def ulid({:id, id}) when is_binary(id), do: ulid(id)
  def ulid(%{"id" => id}) when is_binary(id), do: ulid(id)
  def ulid(ids) when is_list(ids), do: ids |> maybe_flatten() |> Enum.map(&ulid/1) |> filter_empty(nil)
  def ulid({:ok, other}), do: ulid(other)
  def ulid(id) do
    if is_ulid?(id) do
      id
    else
      e = "Utils.ulid/1: Expected a ULID ID (or an object with one), got #{inspect id}"
      # throw {:error, e}
      warn(e)
      nil
    end
  end

  @doc """
  Attempt geting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def map_get(map, key, fallback) when is_map(map) and is_atom(key) do
    maybe_get(map, key,
      map_get(map, Atom.to_string(key), fallback)
    ) |> magic_filter_empty(map, key, fallback)
  end

  #doc """ Attempt geting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback """
  def map_get(map, key, fallback) when is_map(map) and is_binary(key) do
    Map.get(
      map,
      key,
      Map.get(
        map,
        Recase.to_camel(key),
        Map.get(
          map,
          maybe_to_atom(key),
          fallback
        )
      )
    ) |> magic_filter_empty(map, key, fallback)
  end

  #doc "Try with each key in list"
  def map_get(map, keys, fallback) when is_list(keys) do
    Enum.map(keys, &map_get(map, &1, nil))
    |> Enum.filter(&(&1))
    || fallback
  end

  def map_get(map, key, fallback), do: maybe_get(map, key, fallback)

  def maybe_get(_, _, fallback \\ nil)
  def maybe_get(%{} = map, key, fallback), do: Map.get(map, key, fallback) |> magic_filter_empty(map, key, fallback)
  def maybe_get(_, _, fallback), do: fallback

  def magic_filter_empty(val, map, key, fallback \\ nil)
  def magic_filter_empty(%Ecto.Association.NotLoaded{}, %{__struct__: schema} = map, key, fallback) when is_map(map) and is_atom(key) do
    if Config.get!(:env) == :dev && Config.get(:e_auto_preload, false) do
      warn("The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the orginal query...")
      Bonfire.Repo.maybe_preload(map, key) |> Map.get(key, fallback) |> filter_empty(fallback)
    else
      debug("e() requested #{key} of #{schema} but that was not preloaded in the original query.")
      fallback
    end
  end
  def magic_filter_empty(val, _, _, fallback), do: val |> filter_empty(fallback)

  def filter_empty(val, fallback)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback
  def filter_empty(map, fallback) when is_map(map) and map==%{}, do: fallback
  def filter_empty([], fallback), do: fallback
  def filter_empty(list, fallback) when is_list(list), do: list |> Enum.map(&sub_filter_empty/1) |> Enum.filter(& &1) |> re_filter_empty(fallback)
  # def filter_empty(enum, fallback) when is_list(enum) or is_map(enum), do: Enum.map(enum, &filter_empty(&1, fallback))
  def filter_empty(val, fallback), do: val || fallback

  defp sub_filter_empty(%Ecto.Association.NotLoaded{}), do: nil
  defp sub_filter_empty([]), do: nil
  defp sub_filter_empty({:error, _}), do: nil
  defp sub_filter_empty(map) when is_map(map) and map==%{}, do: nil
  defp sub_filter_empty(""), do: nil
  defp sub_filter_empty(val), do: val

  defp re_filter_empty([], fallback), do: fallback
  defp re_filter_empty(val, _fallback), do: val

  def uniq_by_id(list) do
    list
    |> Enum.uniq_by(&e(&1, :id, &1))
  end

  def put_new_in(%{} = map, [key], val) do
    Map.put_new(map, key, val)
  end

  def put_new_in(%{} = map, [key | path], val) when is_list(path) do
    {_, ret} =
      Map.get_and_update(map, key, fn existing ->
        {val, put_new_in(existing || %{}, path, val)}
      end)

    ret
  end

  @doc "Rename a key in a map"
  def map_key_replace(%{} = map, key, new_key, new_value \\ nil) do
    map
    |> Map.put(new_key, new_value || Map.get(map, key))
    |> Map.delete(key)
  end

  def map_key_replace_existing(%{} = map, key, new_key, new_value \\ nil) do
    if Map.has_key?(map, key) do
      map_key_replace(map, key, new_key, new_value)
    else
      map
    end
  end

  def attr_get_id(attrs, field_name) do
    if is_map(attrs) and Map.has_key?(attrs, field_name) do
      Map.get(attrs, field_name)
      |> ulid()
    end
  end

  @doc "conditionally update a map"
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "recursively merge maps or lists"
  def deep_merge(left = %{}, right = %{}) do
    Map.merge(left, right, &deep_resolve/3)
  end
  def deep_merge(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right), do: Keyword.merge(left, right, &deep_resolve/3),
    else: (left ++ right) |> Enum.uniq()
  end
  def deep_merge(%{} = left, right) when is_list(right) do
    deep_merge(Map.to_list(left), right)
  end
  def deep_merge(left, %{} = right) when is_list(left) do
    deep_merge(left, Map.to_list(right))
  end
  def deep_merge(_left, right) do
    right
  end

  # Key exists in both maps - these can be merged recursively.
  defp deep_resolve(_key, left, right) when (is_map(left) or is_list(left)) and (is_map(right) or is_list(right)) do
    deep_merge(left, right)
  end

  # Key exists in both maps or keylists, but at least one of the values is
  # NOT a map or list. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  def deep_merge_reduce([]), do: []
  def deep_merge_reduce([only_one]), do: only_one # to avoid Enum.EmptyError
  def deep_merge_reduce(list_or_map) do
    list_or_map
    |> Enum.reduce(fn elem, acc ->
      deep_merge(acc, elem)
    end)
  end

  def assign_global(socket, assigns) when is_map(assigns), do: assign_global(socket, Map.to_list(assigns))
  def assign_global(socket, assigns) when is_list(assigns) do
    socket
    |> Phoenix.LiveView.assign(assigns)
    # being naughty here, let's see how long until Surface breaks it:
    |> Phoenix.LiveView.assign(:__context__,
                          Map.get(socket.assigns, :__context__, %{})
                          |> Map.merge(maybe_to_map(assigns))
    ) #|> debug("assign_global")
  end
  def assign_global(socket, {_, _} = assign) do
    assign_global(socket, [assign])
  end
  def assign_global(socket, assign, value) do
    assign_global(socket, {assign, value})
  end
  # def assign_global(socket, assign, value) do
  #   socket
  #   |> Phoenix.LiveView.assign(assign, value)
  #   |> Phoenix.LiveView.assign(:global_assigns, [assign] ++ Map.get(socket.assigns, :global_assigns, []))
  # end

  # TODO: get rid of assigning everything to a component, and then we'll no longer need this
  def assigns_clean(%{} = assigns) when is_map(assigns), do: assigns_clean(Map.to_list(assigns))
  def assigns_clean(assigns) do
    (
    assigns
    ++ [{:current_user, current_user(assigns)}]
    ) # temp workaround
    # |> IO.inspect
    |> Enum.reject( fn
      {key, _} when key in [
        :id,
        :flash,
        :__changed__,
        # :__context__,
        :__surface__,
        :socket
      ] -> true
      _ -> false
    end)
    # |> IO.inspect
  end

  def assigns_minimal(%{} = assigns) when is_map(assigns), do: assigns_minimal(Map.to_list(assigns))
  def assigns_minimal(assigns) do

    preserve_global_assigns = Keyword.get(assigns, :global_assigns, []) || [] #|> IO.inspect

    assigns
    # |> IO.inspect
    |> Enum.reject( fn
      {:current_user, _} -> false
      {:current_account, _} -> false
      {:global_assigns, _} -> false
      {assign, _} -> assign not in preserve_global_assigns
      _ -> true
    end)
    # |> IO.inspect
  end

  def assigns_merge(%Phoenix.LiveView.Socket{} = socket, assigns, new) when is_map(assigns) or is_list(assigns), do: socket |> Phoenix.LiveView.assign(assigns_merge(assigns, new))
  def assigns_merge(assigns, new) when is_map(assigns), do: assigns_merge(Map.to_list(assigns), new)
  def assigns_merge(assigns, new) when is_map(new), do: assigns_merge(assigns, Map.to_list(new))
  def assigns_merge(assigns, new) when is_list(assigns) and is_list(new) do

    assigns
    |> assigns_clean()
    |> deep_merge(new)
    # |> IO.inspect
  end

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  def maybe_list(val, change_fn) when is_list(val) do
    change_fn.(val)
  end
  def maybe_list(val, _) do
    val
  end

  @spec maybe_ok_error(any, any) :: any
  @doc "Applies change_fn if the first parameter is an {:ok, val} tuple, else returns the value"
  def maybe_ok_error({:ok, val}, change_fn) do
    {:ok, change_fn.(val)}
  end

  def maybe_ok_error(other, _change_fn), do: other

  @doc "Append an item to a list if it is not nil"
  @spec maybe_append([any()], any()) :: [any()]
  def maybe_append(list, value) when is_nil(value) or value == [], do: list
  def maybe_append(list, {:ok, value}) when is_nil(value) or value == [], do: list
  def maybe_append(list, value) when is_list(list), do: [value | list]
  def maybe_append(obj, value), do: maybe_append([obj], value)

  def maybe_to_atom("false"), do: false # not sure why but seems needed
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

  def maybe_str_to_module(str)
  def maybe_str_to_module(str) when is_binary(str) do
    case maybe_to_atom(str) do
      module_or_atom when is_atom(module_or_atom) -> module_or_atom
      "Elixir."<>str -> nil # module doesn't exist
      _ -> maybe_to_atom!("Elixir."<>str)
    end
  end
  def maybe_str_to_module(atom) when is_atom(atom), do: atom
  def maybe_str_to_module(_), do: nil

  def module_to_str(str) when is_binary(str) do
    case str do
      "Elixir."<>name -> name
      other -> other
    end
  end
  def module_to_str(atom) when is_atom(atom), do: maybe_to_string(atom) |> module_to_str()

  def module_to_human_readable(module) do
    module |> module_to_str() |> String.split(".") |> List.last() |> Recase.to_sentence()
  end

  def maybe_to_string(atom) when is_atom(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end
  def maybe_to_string(list) when is_list(list) do
    # IO.inspect(list, label: "list")
    List.to_string(list)
  end
  def maybe_to_string({key, val}) do
    maybe_to_string(key)<>":"<>maybe_to_string(val)
  end
  def maybe_to_string(other) do
    to_string(other)
  end

  def maybe_flatten(list) when is_list(list), do: List.flatten(list)
  def maybe_flatten(other), do: other

  @doc """
  Flattens a list by recursively flattening the head and tail of the list
  """
  def flatter(list), do: list |> do_flatter() |> List.flatten()

  defp do_flatter([head | tail]), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter([]), do: []
  defp do_flatter([element]), do: do_flatter(element)
  defp do_flatter({head, tail}), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter(element), do: element

  def maybe_from_struct(obj) when is_struct(obj), do: struct_to_map(obj)
  def maybe_from_struct(obj), do: obj

  def struct_to_map(struct = %{__struct__: type}) do
    Map.from_struct(struct)
    |> Map.drop([:__meta__])
    |> Map.put_new(:__typename, type)
    |> map_filter_empty() #|> debug("clean")
  end
  def struct_to_map(other), do: other

  def maybe_to_map(obj, recursive \\ false)
  def maybe_to_map(struct = %{__struct__: _}, false), do: struct_to_map(struct)
  def maybe_to_map(data, false) when is_list(data), do: Enum.into(data, %{})
  def maybe_to_map(data, false) when not is_tuple(data), do: data
  def maybe_to_map(data, false) do
    data
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [a, b] -> {a, b} end)
  end
  def maybe_to_map(struct = %{__struct__: _}, true), do: maybe_to_map(struct_to_map(struct), true)
  def maybe_to_map({a, b}, true), do: %{a => maybe_to_map(b, true)}
  def maybe_to_map(data, true) when not is_list(data), do: data
  def maybe_to_map(data, true) do
    data
    |> Enum.map(&maybe_to_map(&1, true))
    |> Enum.into(%{})
  end

  @doc """
  Converts an enumerable to a list recursively
  Note: make sure that all keys are atoms, i.e. using `input_to_atoms` first
  """
  def maybe_to_keyword_list(obj, recursive \\ true)
  def maybe_to_keyword_list(obj, true = recursive) when is_map(obj) or is_list(obj) do
    obj
    |> maybe_to_keyword_list(false)
    |> Keyword.new(fn {k, v} -> {k, maybe_to_keyword_list(v, recursive)} end)
  end
  def maybe_to_keyword_list(obj, false = _recursive) when is_map(obj) or is_list(obj) do
    obj
    |> Enum.filter(fn {k, _v} -> is_atom(k) end)
  end
  def maybe_to_keyword_list(obj, _), do: obj

  def nested_structs_to_maps(struct = %type{}) when not type == DateTime,
    do: nested_structs_to_maps(struct_to_map(struct))
  def nested_structs_to_maps(v) when not is_map(v), do: v
  def nested_structs_to_maps(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {k, nested_structs_to_maps(v)} end)
    |> Enum.into(%{})
  end

  def maybe_merge_to_struct(first, precedence) when is_struct(first), do: struct(first, maybe_from_struct(precedence))
  def maybe_merge_to_struct(%{} = first, precedence) do
    merged = merge_structs_as_map(first, precedence)
    # |> debug()

    case Bonfire.Common.Types.object_type(first) || Bonfire.Common.Types.object_type(precedence) do
      type when is_atom(type) and not is_nil(type) ->
        debug("maybe_merge_to_struct yes: #{inspect type}")
        struct(type, merged)
      other ->
        debug("maybe_merge_to_struct no: #{inspect other}")
        merged
    end
  end
  def maybe_merge_to_struct(nil, precedence), do: precedence
  def maybe_merge_to_struct(first, nil), do: first

  def merge_structs_as_map(%{__typename: type} = target, merge) when not is_struct(target) and not is_struct(merge), do: Map.merge(target, merge) |> Map.put(:__typename, type)
  def merge_structs_as_map(target, merge) when is_struct(target) or is_struct(merge), do: merge_structs_as_map(maybe_from_struct(target), maybe_from_struct(merge))
  def merge_structs_as_map(target, merge) when not is_struct(target) and not is_struct(merge), do: Map.merge(target, merge)

  def maybe_convert_ulids(list) when is_list(list), do: Enum.map(list, &maybe_convert_ulids/1)

  def maybe_convert_ulids(%{} = map) do
    map |> Enum.map(&maybe_convert_ulids/1) |> Map.new
  end
  def maybe_convert_ulids({key, val}) when byte_size(val) == 16 do
    with {:ok, ulid} <- Pointers.ULID.load(val) do
      {key, ulid}
    else _ ->
      {key, val}
    end
  end
  def maybe_convert_ulids({:ok, val}), do: {:ok, maybe_convert_ulids(val)}
  def maybe_convert_ulids(val), do: val


  def map_filter_empty(data) when is_map(data) and not is_struct(data) do
    Enum.map(data, &map_filter_empty/1) |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  def map_filter_empty({k, v}) do
    {k, map_filter_empty(v)}
  end

  def map_filter_empty(v) do
    filter_empty(v, nil)
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(map, recursive \\ true)

  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(map = %{}, true) do
    map
    |> maybe_to_map()
    |> Enum.map(fn {k, v} ->
        {
          maybe_to_string(k),
          stringify_keys(v)
        }
      end)
    |> Enum.into(%{})
  end

  def stringify_keys(map = %{}, _) do
    map
    |> maybe_to_map()
    |> Enum.map(fn {k, v} -> {maybe_to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Walk a list and stringify the keys of
  # of any map members
  def stringify_keys([head | rest], recursive) do
    [stringify_keys(head, recursive) | stringify_keys(rest, recursive)]
  end

  def stringify_keys(not_a_map, _recursive) do
    not_a_map
  end

  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  def replace_nil(nil, value), do: value
  def replace_nil(other, _), do: other


  def input_to_atoms(data, discard_unknown_keys \\ true, including_values \\ false)
  def input_to_atoms(data, _, _) when is_struct(data) do # skip structs
    data
  end
  def input_to_atoms(%{} = data, true = discard_unknown_keys, including_values) do
    # turn any keys into atoms (if such atoms already exist) and discard the rest
    :maps.filter(fn k, _v -> is_atom(k) end,
      data
      |> Map.drop(["_csrf_token"])
      |> Map.new(fn {k, v} -> {
        maybe_to_snake_atom(k) || maybe_str_to_module(k),
        input_to_atoms(v, discard_unknown_keys, including_values)
      } end)
    )
  end
  def input_to_atoms(%{} = data, false = discard_unknown_keys, including_values) do
    data
    |> Map.drop(["_csrf_token"])
    |> Map.new(fn {k, v} -> {
      (maybe_to_snake_atom(k) || maybe_str_to_module(k) || k),
      input_to_atoms(v, discard_unknown_keys, including_values)
    } end)
  end
  def input_to_atoms(list, true = _discard_unknown_keys, including_values) when is_list(list) do
    list = Enum.map(list, &input_to_atoms(&1, true, including_values))
    if Keyword.keyword?(list) do
      Keyword.filter(list, fn {k, _v} -> is_atom(k) end)
    else
      list
    end
  end
  def input_to_atoms(list, _, including_values) when is_list(list) do
    Enum.map(list, &input_to_atoms(&1, false, including_values))
  end
  def input_to_atoms(v, _, true = _including_values) do
    case maybe_str_to_module(v) do
      nil -> v # do it this roundabout way to support `false` as a value
      other -> other
    end
  end
  def input_to_atoms(v, _, _), do: v

  def maybe_to_snake(string), do: Recase.to_snake("#{string}")

  def maybe_to_snake_atom(string), do: maybe_to_atom!(maybe_to_snake(string))

  def maybe_to_structs(v) when is_struct(v), do: v
  def maybe_to_structs(v), do: v |> input_to_atoms() |> maybe_to_structs_recurse()

  defp maybe_to_structs_recurse(data, parent_id \\ nil)
  defp maybe_to_structs_recurse(%{index_type: type} = data, parent_id) do
    data
    |> Map.new(fn {k, v} -> {k, maybe_to_structs_recurse(v, e(data, :id, nil))} end)
    |> maybe_add_mixin_id(parent_id)
    |> maybe_to_struct(type)
  end
  defp maybe_to_structs_recurse(%{} = data, parent_id) do
    data
    |> Map.new(fn {k, v} -> {k, maybe_to_structs_recurse(v, e(data, :id, nil))} end)
  end
  defp maybe_to_structs_recurse(v, _), do: v

  defp maybe_add_mixin_id(%{id: id} = data, _parent_id) when not is_nil(id), do: data
  defp maybe_add_mixin_id(data, parent_id) when not is_nil(parent_id), do: Map.merge(data, %{id: parent_id})
  defp maybe_add_mixin_id(data, parent_id), do: data

  def maybe_to_struct(obj, type \\ nil)
  def maybe_to_struct(%{__struct__: struct_type} = obj, target_type) when target_type == struct_type, do: obj
  def maybe_to_struct(obj, type) when is_struct(obj) do
    maybe_from_struct(obj) |> maybe_to_struct(type)
  end
  def maybe_to_struct(obj, type) when is_binary(type) do
    case maybe_str_to_module(type) do
      module when is_atom(module) -> maybe_to_struct(obj, module)
      _ -> obj
    end
  end
  def maybe_to_struct(obj, module) when is_atom(module) do
    debug("to_struct with module #{module}")
    # if module_enabled?(module) and module_enabled?(Mappable) do
    #   Mappable.to_struct(obj, module)
    # else
      if module_enabled?(module), do: struct(module, obj),
      else: obj
    # end
  end
  def maybe_to_struct(%{index_type: type} = obj, _type), do: maybe_to_struct(obj, type) # for search results
  def maybe_to_struct(%{__typename: type} = obj, _type), do: maybe_to_struct(obj, type) # for graphql queries
  def maybe_to_struct(obj, _type), do: obj

  def struct_from_map(a_map, as: a_struct) do # MIT licensed function by Kum Sackey
    keys = Map.keys(Map.delete(a_struct, :__struct__))
    # Process map, checking for both string / atom keys
    for(key <- keys, into: %{}, do: {key, Map.get(a_map, key) || Map.get(a_map, to_string(key))})
    |> Map.merge(a_struct, ...)
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> binary_part(0, length)
  end

  def md(content), do: Phoenix.HTML.raw(markdown(content)) # for use in views
  def markdown(content), do: Text.markdown_to_html(content)

  def rich(content) do
    case content do
      _ when is_binary(content) ->
        # if Text.is_html?(content), do: r(content), else:
          md(content)
      {:ok, msg} when is_binary(msg) -> rich(msg)
      {:ok, _} ->
        debug(content)
        l "Ok"
      {:error, msg} when is_binary(msg) -> rich(msg)
      {:error, _} ->
        error(content)
        l "Error"
      _ when is_map(content) ->
        error(content, "Unexpected data")
        l "Unexpected data"
      _ when is_nil(content) or content=="" -> nil
      %Ecto.Association.NotLoaded{} -> nil
      _  -> rich(inspect content)
    end
  end

  def text_only(html), do: HtmlSanitizeEx.strip_tags(html)

  def date_relative(%{id: id}), do: date_from_pointer(id) |> date_relative()
  def date_relative(date) do
    date
    |> Timex.format("{relative}", :relative)
    |> with({:ok, relative} <- ...) do
      relative
    else
      other ->
        error(date, inspect other)
        ""
    end
  end

  def date_from_now(date), do: date_relative(date)

  def date_from_pointer(%{id: id}), do: date_from_pointer(id)
  def date_from_pointer(id) when is_binary(id) do
    with {:ok, ts} <- Pointers.ULID.timestamp(id) |> debug(),
    {:ok, date} <- DateTime.from_unix(ts, :millisecond) do
      date
    else e ->
      error(e)
      nil
    end
  end
  def date_from_pointer(other) do
    error(other, "no pattern match")
    nil
  end

  def media_url(%{media_type: media_type} = media) do
    if String.starts_with?(media_type, "image") do
      image_url(media)
    else
      Bonfire.Files.DocumentUploader.remote_url(media)
    end
  end

  def avatar_url(%{profile: %{icon: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url
  def avatar_url(%{icon: %{id: _} = media}), do: Bonfire.Files.IconUploader.remote_url(media)
  def avatar_url(%{icon_id: icon_id}) when is_binary(icon_id), do: Bonfire.Files.IconUploader.remote_url(icon_id)
  def avatar_url(%{path: _} = media), do: Bonfire.Files.IconUploader.remote_url(media)
  def avatar_url(%{icon: url}) when is_binary(url), do: url
  def avatar_url(%{image: url}) when is_binary(url), do: url # handle VF API
  def avatar_url(%{id: id, shared_user: nil}), do: Bonfire.Me.Fake.avatar_url(id) # robohash
  def avatar_url(%{id: id, shared_user: %{id: _}} = obj), do: "https://picsum.photos/seed/#{id}/128/128?blur" # for Teams/Orgs
  # def avatar_url(%{id: id, shared_user: _} = user), do: Bonfire.Repo.maybe_preload(user, :shared_user) |> avatar_url() # TODO: make sure this is preloaded in user queries when we need it
  # def avatar_url(obj), do: image_url(obj)
  def avatar_url(%{id: id}), do: Bonfire.Me.Fake.avatar_url(id) # robohash
  def avatar_url(_obj), do: Bonfire.Me.Fake.avatar_url()

  def image_url(%{profile: %{image: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url
  def image_url(%{image: %{id: _} = media}), do: Bonfire.Files.ImageUploader.remote_url(media)
  def image_url(%{path: _} = media), do: Bonfire.Files.ImageUploader.remote_url(media)
  def image_url(%{image_id: image_id}) when is_binary(image_id), do: Bonfire.Files.ImageUploader.remote_url(image_id)
  def image_url(%{image: url}) when is_binary(url), do: url
  def image_url(%{profile: profile}), do: image_url(profile)

  # WIP: https://github.com/bonfire-networks/bonfire-app/issues/151#issuecomment-1060536119

  # def image_url(%{name: name}) when is_binary(name), do: "https://loremflickr.com/600/225/#{name}/all?lock=1"
  # def image_url(%{note: note}) when is_binary(note), do: "https://loremflickr.com/600/225/#{note}/all?lock=1"
  # def image_url(%{id: id}), do: "https://picsum.photos/seed/#{id}/600/225?blur"
  # def image_url(_obj), do: "https://picsum.photos/600/225?blur"

  # If no background image is provided, default to a default one (It can be included in configurations)
  def image_url(_obj), do: "/images/bonfires.png"

  # def image_url(_obj), do: Bonfire.Me.Fake.image_url()

  def current_user(current_user_or_socket_or_opts) do
    case current_user_or_socket_or_opts do
      %{current_user: %{}=user} = _options  -> user
      %{context: context}       = _api_opts -> current_user(context)
      %{__context__: context}   = _assigns  -> current_user(context)
      %{assigns: assigns}       = _socket   -> current_user(assigns)
      %{socket: socket}         = _socket   -> current_user(socket)
      %{id: _, profile: _}      = user      -> user
      %{id: _, character: _}    = user      -> user
      options when is_list(options)         -> current_user(Map.new(options))
      other ->
        debug("No current_user found in #{inspect other}")
        nil
    end
  end

  def to_options(current_user_or_socket_or_opts) do
    case current_user_or_socket_or_opts do
      %{current_user: %{}=user} = _options  -> [current_user: user]
      %{context: context}       = _api_opts -> to_options(context)
      %{__context__: context}   = _assigns  -> to_options(context)
      %{assigns: assigns}       = _socket   -> to_options(assigns)
      %{socket: socket}         = _socket   -> to_options(socket)
      %{id: _, profile: _}      = user      -> [current_user: user]
      %{id: _, character: _}    = user      -> [current_user: user]
      list when is_list(list)               -> list
      other ->
        debug("No current_user found in #{inspect other}")
        []
    end
  end

  def maybe_from_opts(opts, key, fallback \\ nil) when is_list(opts), do: opts[key] || fallback
  def maybe_from_opts(_opts, _key, fallback), do: fallback

  def current_account(%{current_account: current_account} = _assigns) when not is_nil(current_account) do
    current_account
  end
  def current_account(%Bonfire.Data.Identity.Account{id: _} = current_account) do
    current_account
  end
  def current_account(%{accounted: %{account: %{id: _} = account}} = _user) do
    account
  end
  def current_account(%{context: context} = _api_opts) do
    current_account(context)
  end
  def current_account(%{__context__: context} = _assigns) do
    current_account(context)
  end
  def current_account(%{assigns: assigns} = _socket) do
    current_account(assigns)
  end
  def current_account(%{socket: socket} = _socket) do
    current_account(socket)
  end
  def current_account(other) when is_map(other) do
    case current_user(other) do
      nil ->
        debug("No current_account found in #{inspect other}")
        nil
      user ->
        case user
        |> Bonfire.Repo.maybe_preload(accounted: :account) do
          %{accounted: %{account: account}} -> account
          _ -> nil
        end
    end
  end
  def current_account(other) do
    debug("No current_account found in #{inspect other}")
    nil
  end

  # defdelegate content(conn, name, type, opts \\ [do: ""]), to: Bonfire.Common.Web.ContentAreas

  @doc """
  Special LiveView helper function which allows loading LiveComponents in regular Phoenix views: `live_render_component(@conn, MyLiveComponent)`
  """
  def live_render_component(conn, load_live_component) do
    if module_enabled?(load_live_component),
      do:
        Phoenix.LiveView.Controller.live_render(
          conn,
          Bonfire.Web.LiveComponent,
          session: %{
            "load_live_component" => load_live_component
          }
        )
  end

  def live_render_with_conn(conn, live_view) do
    Phoenix.LiveView.Controller.live_render(conn, live_view, session: %{"conn" => conn})
  end

  def macro_inspect(fun) do
      fun.() |> Macro.expand(__ENV__) |> Macro.to_string |> debug("Macro:")
  end

  def ok_or(ret, fallback \\ nil) do
    with {:ok, val} <- ret do
      val
    else _ ->
      fallback
    end
  end

  def elem_or(verb, index, _fallback) when is_tuple(verb), do: elem(verb, index)
  def elem_or(_verb, _index, fallback), do: fallback

  def contains?(string, substring) when is_binary(string) and is_binary(substring), do: string =~ substring
  def contains?(_, _), do: nil


  @doc """
  Subscribe to something for realtime updates, like a feed or thread
  """
  # def pubsub_subscribe(topics, socket \\ nil)

  def pubsub_subscribe(topics, socket) when is_list(topics) do
    Enum.each(topics, &pubsub_subscribe(&1, socket))
  end

  def pubsub_subscribe(topic, %Phoenix.LiveView.Socket{} = socket) when is_binary(topic) do
    # debug(socket)
    if socket_connected_or_user?(socket) do
      pubsub_subscribe(topic)
    else
      debug("PubSub: LiveView is not connected so we skip subscribing to #{inspect topic}")
    end
  end

  def pubsub_subscribe(topic, _) when is_binary(topic), do: pubsub_subscribe(topic)

  def pubsub_subscribe(topic, socket) when not is_binary(topic) do
    with t when is_binary(t) <- maybe_to_string(topic) do
      debug("PubSub: transformed the topic #{inspect topic} into a string we can subscribe to: #{inspect t}")
      pubsub_subscribe(t, socket)
    else _ ->
      warn("PubSub: could not transform the topic into a string we can subscribe to: #{inspect topic}")
    end
  end

  def pubsub_subscribe(topic, _) do
    warn("PubSub can not subscribe to a non-string topic: #{inspect topic}")
    false
  end

  defp pubsub_subscribe(topic) when is_binary(topic) and topic !="" do
    debug("PubSub subscribed to: #{topic}")

    endpoint = Config.get(:endpoint_module, Bonfire.Web.Endpoint)

    # endpoint.unsubscribe(maybe_to_string(topic)) # to avoid duplicate subscriptions?
    endpoint.subscribe(topic)
    # Phoenix.PubSub.subscribe(Bonfire.PubSub, topic)
  end

  defp socket_connected_or_user?(%Phoenix.LiveView.Socket{}), do: true
  defp socket_connected_or_user?(%Bonfire.Data.Identity.User{}), do: true
  defp socket_connected_or_user?(_), do: false

  @doc """
  Broadcast some data for realtime updates, for example to a feed or thread
  """
  def pubsub_broadcast(topics, payload) when is_list(topics) do
    Enum.each(topics, &pubsub_broadcast(&1, payload))
  end

  def pubsub_broadcast(topic, {payload_type, _data} = payload) do
    debug("pubsub_broadcast: #{inspect topic} / #{inspect payload_type}")
    do_broadcast(topic, payload)
  end
  def pubsub_broadcast(topic, data)
  when (is_atom(topic) or is_binary(topic)) and topic !="" and not is_nil(data) do
    debug("pubsub_broadcast: #{inspect topic}")
    do_broadcast(topic, data)
  end
  def pubsub_broadcast(_, _), do: warn("pubsub did not broadcast")

  defp do_broadcast(topic, data) do
    # endpoint = Config.get(:endpoint_module, Bonfire.Web.Endpoint)
    # endpoint.broadcast_from(self(), topic, step, state)
    Phoenix.PubSub.broadcast(Bonfire.PubSub, maybe_to_string(topic), data)
  end


  def assigns_subscribe(%Phoenix.LiveView.Socket{} = socket, assign_names)
  when is_list(assign_names) or is_atom(assign_names) or is_binary(assign_names) do

    # subscribe to god-level assign + object ID based assign if ID provided in tuple
    names_of_assign_topics(assign_names)
    |> pubsub_subscribe(socket)

    socket
    |> self_subscribe(assign_names) # also subscribe to assigns for current user
  end

  @doc "Subscribe to assigns targeted at the current account/user"
  def self_subscribe(%Phoenix.LiveView.Socket{} = socket, assign_names)
  when is_list(assign_names) or is_atom(assign_names) or is_binary(assign_names) do
    target_ids = current_account_and_or_user_ids(socket)
    if is_list(target_ids) and target_ids != [] do
      target_ids
      |> names_of_assign_topics(assign_names)
      |> pubsub_subscribe(socket)
    else
      debug(target_ids, "cannot_self_subscribe")
    end
    socket
  end


  def cast_self(socket, assigns_to_broadcast) do
    assign_target_ids = current_account_and_or_user_ids(socket)

    if assign_target_ids do
      socket |> assign_and_broadcast(assigns_to_broadcast, assign_target_ids)
    else
      debug("cast_self: Cannot send via PubSub without an account and/or user in socket. Falling back to only setting an assign.")
      socket |> assign_global(assigns_to_broadcast)
    end
  end


  @doc "Warning: this will set assigns for any/all users who subscribe to them. You want to `cast_self/2` instead if dealing with user-specific actions or private data."
  def cast_public(socket, assigns_to_broadcast) do
    socket |> assign_and_broadcast(assigns_to_broadcast)
  end


  defp assign_and_broadcast(socket, assigns_to_broadcast, assign_target_ids \\ []) do
    assigns_broadcast(assigns_to_broadcast, assign_target_ids)
    socket |> assign_global(assigns_to_broadcast)
  end

  defp assigns_broadcast(assigns, assign_target_ids \\ [])
  defp assigns_broadcast(assigns, assign_target_ids) when is_list(assigns) do
    Enum.each(assigns, &assigns_broadcast(&1, assign_target_ids))
  end
  # defp assigns_broadcast({{assign_name, assign_id}, data}, assign_target_ids) do
  #   names_of_assign_topics([assign_id] ++ assign_target_ids, assign_name)
  #   |> pubsub_broadcast({:assign, {assign_name, data}})
  # end
  defp assigns_broadcast({assign_name, data}, assign_target_ids) do
    names_of_assign_topics(assign_target_ids, assign_name)
    |> pubsub_broadcast({:assign, {assign_name, data}})
  end

  defp names_of_assign_topics(assign_target_ids \\ [], assign_names)
  defp names_of_assign_topics(assign_target_ids, assign_names) when is_list(assign_names) do
    Enum.map(assign_names, &names_of_assign_topics(assign_target_ids, &1))
  end
  defp names_of_assign_topics(assign_target_ids, {assign_name, assign_id}) do
    names_of_assign_topics([assign_id] ++ assign_target_ids, assign_name)
  end
  defp names_of_assign_topics(assign_target_ids, assign_name) when is_list(assign_target_ids) and length(assign_target_ids)>0 do
    debug(assign_identified_object: {assign_name, assign_target_ids})
    [{:assign, assign_name}] ++ assign_target_ids
    |> Enum.map(&maybe_to_string/1)
    |> Enum.join(":")
  end
  defp names_of_assign_topics(_, assign_name) do
    debug(assign_god_level_object: {assign_name})
    {:assign, assign_name}
  end

  def current_account_and_or_user_ids(%{assigns: assigns}), do: current_account_and_or_user_ids(assigns)
  def current_account_and_or_user_ids(%{current_account: %{id: account_id}, current_user: %{id: user_id}}) do
    [{:account, account_id}, {:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_user: %{id: user_id, accounted: %{account_id: account_id}, }}) do
    [{:account, account_id}, {:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_user: %{id: user_id}}) do
    [{:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_account: %{id: account_id}}) do
    [{:account, account_id}]
  end
  def current_account_and_or_user_ids(%{__context__: context}), do: current_account_and_or_user_ids(context)
  def current_account_and_or_user_ids(_), do: nil


  @doc """
  Run a function and expects tuple.
  If anything else is returned, like an error, a flash message is shown to the user.
  """
  def undead_mount(socket, fun), do: undead(socket, fun, {:mount, :ok})
  def undead_params(socket, fun), do: undead(socket, fun, {:mount, :noreply})

  def undead(socket, fun, return_key \\ :noreply) do
    fun.()
    # |> debug()
    |> undead_error(socket, return_key)
  rescue
    error in Ecto.Query.CastError ->
      live_exception(socket, return_key, "You seem to have provided an incorrect data type (eg. an invalid ID)", error, __STACKTRACE__)
    error in Ecto.ConstraintError ->
      live_exception(socket, return_key, "You seem to be referencing an invalid object ID, or trying to insert duplicated data", error, __STACKTRACE__)
    error in FunctionClauseError ->
      # debug(error)
      with %{
        arity: arity,
        function: function,
        module: module
      } <- error do
        live_exception(socket, return_key, "The function #{function}/#{arity} in module #{module} didn't receive data in a format it can recognise", error, __STACKTRACE__)
      else error ->
        live_exception(socket, return_key, "A function didn't receive data in a format it can recognise", error, __STACKTRACE__)
      end
    error in WithClauseError ->
      with %{
        term: provided
      } <- error do
        live_exception(socket, return_key, "A 'with condition' didn't receive data in a format it can recognise", provided, __STACKTRACE__)
      else error ->
        live_exception(socket, return_key, "A 'with condition' didn't receive data in a format it can recognise", error, __STACKTRACE__)
      end
    cs in Ecto.Changeset ->
        live_exception(socket, return_key, "The data provided caused an exceptional error and could do not be inserted or updated: "<>error_msg(cs), cs, nil)
    error ->
      live_exception(socket, return_key, "The app encountered an unexpected error", error, __STACKTRACE__)
  catch
    :exit, error ->
      live_exception(socket, return_key, "An exceptional error caused the operation to stop", error, __STACKTRACE__)
    :throw, error ->
      live_exception(socket, return_key, "An exceptional error was thrown", error, __STACKTRACE__)
    error ->
      # error(error)
      live_exception(socket, return_key, "An exceptional error occured", error, __STACKTRACE__)
  end

  def undead_error(error, socket, return_key \\ :noreply) do
   case error do
      {:ok, %Phoenix.LiveView.Socket{} = socket} -> {:ok, socket}
      {:ok, %Phoenix.LiveView.Socket{} = socket, data} -> {:ok, socket, data}
      {:noreply, %Phoenix.LiveView.Socket{} = socket} -> {:noreply, socket}
      {:reply, data, %Phoenix.LiveView.Socket{} = socket} -> {:reply, data, socket}
      {:error, reason} -> undead_error(reason, socket, return_key)
      {:error, reason, extra} -> live_exception(socket, return_key, "There was an error: #{inspect reason}", extra)
      :ok -> {return_key, socket} # shortcut to return nothing
      {:ok, _other} -> {return_key, socket}
      %Ecto.Changeset{} = cs -> live_exception(socket, return_key, "The data provided seems invalid and could not be inserted or updated: "<>error_msg(cs), cs)
      %{__struct__: struct} = act when struct == Bonfire.Epics.Act -> live_exception(socket, return_key, "The act was not completed: ", act)
      %{__struct__: struct} = epic when struct == Bonfire.Epics.Epic -> live_exception(socket, return_key, "There epic was not completed: "<>error_msg(epic), epic.errors)
      not_found when not_found in [:not_found, "Not found", 404] -> live_exception(socket, return_key, "Not found")
      msg when is_binary(msg) -> live_exception(socket, return_key, msg)
      ret -> live_exception(socket, return_key, "Oops, this resulted in something unexpected", ret)
    end
  end

  defp live_exception(socket, return_key, msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  defp live_exception(socket, {:mount, return_key}, msg, exception, stacktrace, kind) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, error_msg(msg)) |> push_redirect(to: "/error")}
    end
  end

  defp live_exception(%{assigns: %{__context__: %{current_url: current_url}}} = socket, return_key, msg, exception, stacktrace, kind) when is_binary(current_url) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, error_msg(msg)) |> push_patch(to: current_url)}
    end
  end

  defp live_exception(socket, return_key, msg, exception, stacktrace, kind) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, error_msg(msg)) |> push_patch(to: path(socket.view))}
    end
  rescue
    FunctionClauseError -> # for cases where the live_path may need param(s) which we don't know about
      {return_key, put_flash(socket, :error, error_msg(msg)) |> push_redirect(to: "/error")}
  end

  def debug_exception(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_exception(%Ecto.Changeset{} = cs, exception, stacktrace, kind) do
    debug_exception(EctoSparkles.Changesets.Errors.changeset_errors_string(cs), exception, stacktrace, kind)
  end

  def debug_exception(msg, exception, stacktrace, kind) do

    debug_log(msg, exception, stacktrace, kind)

    if Config.get!(:env) == :dev and Config.get(:show_debug_errors_in_dev) !=false do

      {exception, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      {:error, Enum.join([error_msg(msg), exception, stacktrace] |> filter_empty([]), "\n") |> String.slice(0..1000) }
    else
      {:error, error_msg(msg)}
    end
  end

  def debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_log(msg, exception, stacktrace, kind) do

   error(msg)

    # if exception, do: Logger.error(debug_banner(kind, exception, stacktrace))
    # if exception, do: IO.puts(Exception.format_exit(exception))
    # if stacktrace, do: IO.inspect(Exception.format_stacktrace(stacktrace), limit: :infinity, printable_limit: :infinity)

    if exception && stacktrace, do:
      IO.warn(debug_banner(kind, exception, stacktrace), stacktrace),
    else:
      (if exception, do: warn(exception))

    debug_maybe_sentry(msg, exception, stacktrace)
  end

  defp debug_maybe_sentry(msg, {:error, %_{} = exception}, stacktrace), do: debug_maybe_sentry(msg, exception, stacktrace)
  # defp debug_maybe_sentry(msg, exception, stacktrace) when not is_nil(stacktrace) and stacktrace !=[] and is_exception(exception) do # FIXME: sentry lib often crashes
  #   if module_enabled?(Sentry), do: Sentry.capture_exception(
  #     exception,
  #     stacktrace: stacktrace,
  #     extra: inspect msg
  #   )
  # end
  defp debug_maybe_sentry(msg, error, stacktrace) do
    if module_enabled?(Sentry), do: Sentry.capture_message(
      inspect error,
      stacktrace: stacktrace,
      extra: inspect msg
    )
  end
  defp debug_maybe_sentry(_, _, _stacktrace), do: nil

  def debug_banner_with_trace(kind, exception, stacktrace) do
    exception = if exception, do: debug_banner(kind, exception, stacktrace)
    stacktrace = if stacktrace, do: Exception.format_stacktrace(stacktrace)
    {exception, stacktrace}
  end

  defp debug_banner(kind, errors, stacktrace) when is_list(errors) do
    errors
    |> Enum.map(&debug_banner(kind, &1, stacktrace))
    |> Enum.join("\n")
  end

  defp debug_banner(kind, {:error, error}, stacktrace) do
    debug_banner(kind, error, stacktrace)
  end

  defp debug_banner(kind, %{error: error}, stacktrace) do
    debug_banner(kind, error, stacktrace)
  end

  defp debug_banner(_kind, %Ecto.Changeset{} = cs, _) do
    # EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  end

  defp debug_banner(kind, %_{} = exception, stacktrace) when not is_nil(stacktrace) and stacktrace !=[] do
    inspect Exception.format_banner(kind, exception, stacktrace)
  end

  defp debug_banner(_kind, exception, _stacktrace) do
    inspect exception
  end

  def error_msg(errors) when is_list(errors) do
    errors
    |> Enum.map(&error_msg/1)
    |> Enum.join("\n")
  end
  def error_msg(%Ecto.Changeset{} = cs), do: EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  def error_msg(%{message: message}), do: error_msg(message)
  def error_msg({:error, error}), do: error_msg(error)
  def error_msg(%{error: error}), do: error_msg(error)
  def error_msg(%{errors: errors}), do: error_msg(errors)
  def error_msg(message) when is_binary(message), do: message
  def error_msg(message), do: inspect message


  @doc "Helpers for calling hypothetical functions in other modules"
  def maybe_apply(
    module,
    fun,
    args \\ [],
    fallback_fun \\ &apply_error/2
  )

  def maybe_apply(
      module,
      funs,
      args,
      fallback_fun
    )
    when is_atom(module) and is_list(funs) and is_list(args) do

    arity = length(args)

    fallback_fun = if not is_function(fallback_fun), do: &apply_error/2, else: fallback_fun
    fallback_return = if not is_function(fallback_fun), do: fallback_fun

    if module_enabled?(module) do
      debug(module, "module_enabled")

      available_funs = funs |> Enum.reject(fn f -> not Kernel.function_exported?(module, f, arity) end)

      fun = List.first(available_funs)

      if fun do
        debug({fun, arity}, "function_exists")

        try do
          apply(module, fun, args)
        rescue
          e in FunctionClauseError ->
            {exception, stacktrace} = debug_banner_with_trace(:error, e, __STACKTRACE__)
            error(stacktrace, exception)
            e = fallback_fun.(
              "A pattern matching error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
              args
            )
            fallback_return || e
          e in ArgumentError ->
            {exception, stacktrace} = debug_banner_with_trace(:error, e, __STACKTRACE__)
            error(stacktrace, exception)
            e = fallback_fun.(
              "An argument error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
              args
            )
            fallback_return || e
        end
      else
        e = fallback_fun.(
          "None of the functions #{inspect funs} are defined at #{module} with arity #{arity}",
          args
        )
        fallback_return || e
      end
    else
      e = fallback_fun.(
        "No such module (#{module}) could be loaded.",
        args
      )
      fallback_return || e
    end
  end

  def maybe_apply(
      module,
      fun,
      args,
      fallback_fun
    )
    when not is_list(args), do: maybe_apply(
      module,
      fun,
      [args],
      fallback_fun
    )

  def maybe_apply(
      module,
      fun,
      args,
      fallback_fun
    )
    when not is_list(fun), do: maybe_apply(
      module,
      [fun],
      args,
      fallback_fun
    )

  def maybe_apply(
      module,
      fun,
      args,
      fallback_fun
    ), do: apply_error("invalid function call for #{inspect fun} on #{inspect module}", args)

  def apply_error(error, args) do
    error("maybe_apply: #{error} - with args: (#{inspect args})")

    {:error, error}
  end
end
