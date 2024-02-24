# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Enums do
  @moduledoc "Extra functions to manipulate enumerables, basically an extension of `Enum`"
  use Arrows
  import Untangle
  import Bonfire.Common.Config, only: [repo: 0]
  import Bonfire.Common.Extend
  alias Ecto.Changeset
  alias Bonfire.Common.Config
  alias Bonfire.Common.Text
  alias Bonfire.Common.Types
  alias Bonfire.Common.Utils

  @compile {:inline, group: 3}

  @doc """
  Extracts a binary ID from various data structures, such as a map containing the key :id or "id", a changeset, or a tuple containing the atom :id.
  """
  def id(id) when is_binary(id), do: id
  def id(%{id: id}) when is_binary(id), do: id
  def id(%Changeset{} = cs), do: id(Changeset.get_field(cs, :id))
  def id({:id, id}) when is_binary(id), do: id
  def id(%{"id" => id}) when is_binary(id), do: id
  def id(%{value: value}), do: id(value)
  def id(%{"value" => value}), do: id(value)
  def id(%{pointer: %{id: id}}), do: id

  def id(ids) when is_list(ids),
    do: ids |> maybe_flatten() |> Enum.map(&id/1) |> filter_empty(nil)

  def id({:ok, other}), do: id(other)

  def id(id) do
    e = "Expected an ID (or an object with one)"
    # throw {:error, e}
    debug(id, e)
    nil
  end

  def ids(objects), do: id(objects) |> List.wrap()

  @doc "Takes an enumerable object and converts it to a map. If it is not an enumerable, a map is created with the data under a fallback key (`:data` by default)."
  def map_new(data, fallback_key \\ :data) do
    if Enumerable.impl_for(data),
      do: Map.new(data),
      else: Map.put(%{}, fallback_key, data)
  end

  @doc """
  Attempt getting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def enum_get(map, key, fallback \\ nil)

  def enum_get(map, key, fallback) when is_map(map) and is_atom(key) do
    case maybe_get(map, key, :empty) do
      :empty -> maybe_get(map, Atom.to_string(key), fallback)
      %Needle.Pointer{deleted_at: del} when not is_nil(del) -> fallback
      val -> val
    end
  end

  # doc """ Attempt getting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback """
  def enum_get(map, key, fallback) when is_map(map) and is_binary(key) do
    case maybe_get(map, key, :empty) do
      :empty ->
        case maybe_get(map, Recase.to_camel(key), :empty) do
          :empty ->
            maybe_get(map, Types.maybe_to_atom(key), fallback)

          %Needle.Pointer{deleted_at: del} when not is_nil(del) ->
            fallback

          val ->
            val
        end

      val ->
        val
    end
  end

  # doc "Try with each key in list"
  def enum_get(map, keys, fallback) when is_list(keys) do
    Enum.map(keys, &enum_get(map, &1, nil))
    |> filter_empty(fallback)
  end

  def enum_get(map, key, fallback), do: maybe_get(map, key, fallback)

  def maybe_get(_, _, fallback \\ nil)

  def maybe_get(%{} = map, key, fallback),
    do:
      Map.get(map, key, fallback)
      |> magic_filter_empty(map, key, fallback)

  def maybe_get(_, _, fallback), do: fallback

  @doc "Checks if the given list contains any duplicates. Takes an optional function that can be used to extract and/or compute the value to compare for each element in the list."
  def has_duplicates?(list, fun \\ nil),
    do: check_has_duplicates?(list, %{}, fun || fn x -> x end)

  defp check_has_duplicates?([], _, _) do
    false
  end

  defp check_has_duplicates?([head | tail], set, fun) do
    value = fun.(head)

    case set do
      %{^value => true} ->
        true

      _ ->
        check_has_duplicates?(tail, Map.put(set, value, true), fun)
    end
  end

  @doc "Takes a list of maps that have an id field and returns a list with only the unique maps. Uniqueness is determined based on the id field and not the full contents of the maps."
  def uniq_by_id(list) do
    list
    |> Enum.uniq_by(&id/1)
    |> filter_empty([])
  end

  @doc """
  This function is used to insert a new value into a nested map data structure, where the path to the location of the value is specified as a list of keys.

  When the path is a single-element list, if the key already exists in the map, it returns the original map; otherwise, it inserts the key-value pair.

  When the path is a list of more than one key, the first element of the list (key) represents the key for the current level of the nested map, and the remaining elements (path) represent the keys for the nested map at the next level. The function starts by retrieving the value at the current level of the map (if it exists) and updates the map with the new value.
  """
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

  defp magic_filter_empty(val, map, key, fallback)

  defp magic_filter_empty(
         %Ecto.Association.NotLoaded{},
         %{__struct__: schema} = map,
         key,
         fallback
       )
       when is_map(map) and is_atom(key) do
    if Config.env() == :dev && Config.get(:e_auto_preload, false) do
      warn(
        "The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the orginal query..."
      )

      repo().maybe_preload(map, key)
      |> Map.get(key, fallback)
      |> filter_empty(fallback)
    else
      debug(
        "Utils.e() requested #{key} of #{schema} but that was not preloaded in the original query."
      )

      fallback
    end
  end

  defp magic_filter_empty(val, _, _, fallback), do: filter_empty(val, fallback)

  @doc "Takes a value and a fallback value. If the value is empty (e.g. an empty map, a non-loaded association, an empty list, an empty string, or nil), the fallback value is returned."
  def filter_empty(val, fallback)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback

  def filter_empty(%Needle.Pointer{deleted_at: del}, fallback) when not is_nil(del),
    do: fallback

  def filter_empty(map, fallback) when is_map(map) and map == %{}, do: fallback
  def filter_empty([], fallback), do: fallback
  def filter_empty("", fallback), do: fallback
  def filter_empty(nil, fallback), do: fallback
  def filter_empty({:error, _}, fallback), do: fallback

  def filter_empty(enum, fallback) when is_list(enum),
    do:
      enum
      |> filter_empty_enum()
      |> re_filter_empty(fallback)

  def filter_empty(enum, fallback) when is_map(enum) and not is_struct(enum),
    do:
      enum
      # |> debug()
      |> filter_empty_enum(true)
      |> Enum.into(%{})
      |> re_filter_empty(fallback)

  def filter_empty(val, _fallback), do: val

  defp filter_empty_enum(enum, filter_keys? \\ false),
    do:
      enum
      |> Enum.map(fn
        {key, val} -> {filter_empty(key, nil), filter_empty(val, nil)}
        val -> filter_empty(val, nil)
      end)
      |> Enum.filter(fn
        {nil, nil} -> false
        {_, nil} when filter_keys? == true -> false
        nil -> false
        _ -> true
      end)

  defp re_filter_empty([], fallback), do: fallback
  defp re_filter_empty(map, fallback) when is_map(map) and map == %{}, do: fallback
  defp re_filter_empty(nil, fallback), do: fallback
  # defp re_filter_empty([val], nil), do: val
  defp re_filter_empty(val, _fallback), do: val

  def filter_empty(%{key: nil}, fallback, key) do
    fallback
  end

  def filter_empty(enum, fallback, key) when is_atom(key) or is_binary(key) do
    case enum_get(enum, key) do
      nil -> fallback
      _ -> filter_empty(enum, fallback)
    end
  end

  # def filter_empty(enum, fallback, keys) when is_list(keys)  do
  #   case enum do
  #     _ when is_map(enum) -> 
  #       enum_keys = Map.keys(enum)
  #       if Enum.any?(keys, fn key -> key in keys end) fallback
  #     nil -> fallback
  #     _ -> filter_empty(enum, fallback)
  #   end
  # end
  # def filter_empty(enum, fallback, key) do
  #   filter_empty(enum, fallback, [key])
  # end

  def maybe_list(val, change_fn) when is_list(val) do
    change_fn.(val)
  end

  def maybe_list(val, _) do
    val
  end

  @doc """
  Takes any element, an index and a fallback value. If the element is a Tuple it returns either the tuple value at that index, otherwise it returns the fallback. If the tuple doesn't contain such an index, it raises `ArgumentError`.
  """
  def maybe_elem(tuple, index, fallback \\ nil)
  def maybe_elem(tuple, index, fallback) when is_tuple(tuple), do: elem(tuple, index)
  def maybe_elem(_, _index, fallback), do: fallback

  @doc "Renames a key in a map. Optionally changes the value as well."
  def map_key_replace(%{} = map, key, new_key, new_value \\ nil) do
    map
    |> Map.put(new_key, new_value || Map.get(map, key))
    |> Map.delete(key)
  end

  @doc """
  Renames a key in a `map`, only if the key exists in the `map`. Optionally changes the value as well.
  """
  def map_key_replace_existing(%{} = map, key, new_key, new_value \\ nil) do
    if Map.has_key?(map, key) do
      map_key_replace(map, key, new_key, new_value)
    else
      map
    end
  end

  @doc """
  Gets the value of a key in a map and returns the ID of that value (i.e. either the :id field of that association, or the value itself).
  """
  def attr_get_id(attrs, field_name) do
    if is_map(attrs) and Map.has_key?(attrs, field_name) do
      Map.get(attrs, field_name)
      |> id()
    end
  end

  @doc """
  Updates a `map` with the given `key` and `value`, but only if the `value` is not `nil`, an empty list or an empty string.
  """
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Recursively merges two data structures (`left` and `right`), which can be structs, maps or lists.
  If `left` and `right` are `Ecto.Changeset`s, `merge_changesets/2` is called on them.
  If `left` is a struct, a similar struct is returned with the merged values.
  If `left` and `right` are lists, they are concatenated unless `:replace_lists` option is set to `true`.
  """
  def deep_merge(left, right, opts \\ [])

  def deep_merge(left, nil, _opts) do
    left
  end

  def deep_merge(%Ecto.Changeset{} = left, %Ecto.Changeset{} = right, _opts) do
    merge_changesets(left, right)
  end

  def deep_merge(left, right, opts) when is_struct(left) do
    struct(left, deep_merge(maybe_to_map(left), right, opts))
  end

  def deep_merge(left, right, opts) when is_map(left) or is_map(right) do
    merge_as_map(left, right, opts ++ [on_conflict: :deep_merge])
  end

  def deep_merge(left, right, opts) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      Keyword.merge(left, right, fn k, v1, v2 ->
        deep_resolve(k, v1, v2, opts)
      end)
    else
      if opts[:replace_lists] do
        right
      else
        Enum.uniq(left ++ right)
      end
    end
  end

  def deep_merge(_left, right, _opts) do
    right
  end

  # Key exists in both maps - these can be merged recursively.
  defp deep_resolve(_key, left, right, opts)

  defp deep_resolve(_key, left, right, opts)
       when (is_map(left) or is_list(left)) and
              (is_map(right) or is_list(right)) do
    deep_merge(left, right, opts)
  end

  # Key exists in both maps or keylists, but at least one of the values is
  # NOT a map or list. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right, _opts) do
    right
  end

  @doc "Deep merges a list of maps into a single map."
  def deep_merge_reduce(list_or_map, opts \\ [])
  def deep_merge_reduce([], _opts), do: %{}
  def deep_merge_reduce(nil, _opts), do: %{}
  # to avoid Enum.EmptyError
  def deep_merge_reduce([only_one], _opts), do: only_one

  def deep_merge_reduce(list_or_map, opts) do
    Enum.reduce(list_or_map, fn elem, acc ->
      deep_merge(acc, elem, opts)
    end)
  end

  def merge_uniq(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      Keyword.merge(left, right, fn _k, _v1, v2 ->
        v2
      end)
    else
      Enum.uniq(left ++ right)
    end
  end

  @doc "Merges two maps or lists into a single map"
  def merge_as_map(left, right, opts \\ [])

  def merge_as_map(%Ecto.Changeset{} = left, %Ecto.Changeset{} = right, _opts) do
    # special case
    merge_changesets(left, right)
  end

  def merge_as_map(left = %{}, right = %{}, opts) do
    # to avoid overriding with empty fields
    right = maybe_to_map(right)

    case opts[:on_conflict] do
      :deep_merge ->
        Map.merge(left, right, fn k, v1, v2 ->
          deep_resolve(k, v1, v2, opts)
        end)

      conflict_fn when is_function(conflict_fn) ->
        Map.merge(left, right, conflict_fn)

      _ ->
        Map.merge(left, right)
    end
  end

  def merge_as_map(left, right, opts) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      merge_as_map(Enum.into(left, %{}), Enum.into(right, %{}), opts)
    else
      if opts[:replace_lists] do
        right
      else
        left ++ right
      end
    end
  end

  def merge_as_map(%{} = left, right, opts) when is_list(right) do
    if Keyword.keyword?(right) do
      merge_as_map(left, Enum.into(right, %{}), opts)
    else
      left
    end
  end

  def merge_as_map(left, %{} = right, opts) when is_list(left) do
    if Keyword.keyword?(left) do
      merge_as_map(Enum.into(left, %{}), right, opts)
    else
      right
    end
  end

  def merge_as_map(_left, right, _) do
    right
  end

  @doc "Merges two `Ecto` changesets. If both changesets have a prepare field, the function concatenates the values of the prepare fields. Either way it also calls `Ecto.Changeset.merge/2` operation."
  def merge_changesets(%Ecto.Changeset{prepare: p1} = cs1, %Ecto.Changeset{prepare: p2} = cs2)
      when is_list(p1) and is_list(p2) and p2 != [] do
    # workaround for `Ecto.Changeset.merge` not merging prepare
    %{Ecto.Changeset.merge(cs1, cs2) | prepare: p1 ++ p2}
  end

  def merge_changesets(%Ecto.Changeset{} = cs1, %Ecto.Changeset{} = cs2) do
    Ecto.Changeset.merge(cs1, cs2)
  end

  @doc "Merges two maps map_1 and map_2, but only keeps the keys that exist in map_1."
  def merge_keeping_only_first_keys(map_1, map_2) do
    map_1
    |> Map.keys()
    |> then(&Map.take(map_2, &1))
    |> then(&Map.merge(map_1, &1))
  end

  @doc "Appends a value to a list, but only if the value is not nil or an empty list. "
  @spec maybe_append([any()], any()) :: [any()]
  def maybe_append(list, value) when is_nil(value) or value == [], do: list

  def maybe_append(list, {:ok, value}) when is_nil(value) or value == [],
    do: list

  def maybe_append(list, value) when is_list(list), do: [value | list]
  def maybe_append(obj, value), do: maybe_append([obj], value)

  @doc "Flattens the list if provided a list, otherwise just return the input"
  def maybe_flatten(list) when is_list(list), do: List.flatten(list)
  def maybe_flatten(other), do: other

  @doc """
  Takes a list and recursively flattens it by recursively flattening the head and tail of the list
  """
  def flatter(list), do: list |> do_flatter() |> maybe_flatten()

  defp do_flatter([element | nil]), do: do_flatter(element)
  defp do_flatter([head | tail]), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter([]), do: []
  defp do_flatter({head, tail}), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter(element), do: element

  @doc "If given a struct, returns a map representation of it"
  def maybe_from_struct(obj) when is_struct(obj), do: struct_to_map(obj)
  def maybe_from_struct(obj), do: obj

  def struct_to_map(struct = %{__struct__: type}) do
    Map.from_struct(struct)
    |> Map.drop([:__meta__])
    |> Map.put_new(:__typename, type)
    # |> debug("clean")
    |> map_filter_empty()
  end

  def struct_to_map(other), do: other

  @doc "Returns a map representation of the input object. If the second argument is `true`, the function will recursively convert nested data structures to maps as well."
  def maybe_to_map(obj, recursive \\ false)
  def maybe_to_map(struct = %{__struct__: _}, false), do: struct_to_map(struct)

  def maybe_to_map(data, false) when is_list(data) do
    if Keyword.keyword?(data), do: Enum.into(data, %{}), else: data
  end

  def maybe_to_map(data, false) when not is_tuple(data), do: data

  def maybe_to_map(data, false) do
    data
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [a, b] -> {a, b} end)
  end

  def maybe_to_map(struct = %{__struct__: _}, true),
    do: maybe_to_map(struct_to_map(struct), true)

  def maybe_to_map({a, b}, true), do: %{a => maybe_to_map(b, true)}
  def maybe_to_map(data, true) when not is_list(data), do: data

  def maybe_to_map(data, true) do
    data
    |> Enum.map(&maybe_to_map(&1, true))
    |> Enum.into(%{})
  end

  @doc """
  Returns a keyword list representation of the input object. If the second argument is `true`, the function will recursively convert nested data structures to keyword lists as well.
  Note: make sure that all keys are atoms, i.e. using `input_to_atoms` first, otherwise the enumerable(s) containing a string key won't be converted.
  """
  def maybe_to_keyword_list(obj, recursive \\ false)

  def maybe_to_keyword_list(obj, true = _recursive)
      when is_map(obj) or is_list(obj) do
    obj
    |> maybe_to_keyword_list_recurse()
  end

  def maybe_to_keyword_list(object, false = _recursive)
      when is_map(object) or is_list(object) do
    maybe_keyword_new(object)
  end

  def maybe_to_keyword_list(obj, _), do: obj

  defp maybe_to_keyword_list_recurse(object) do
    case maybe_keyword_new(object) do
      object when is_map(object) ->
        Map.filter(object, fn
          {k, v} -> {k, maybe_to_keyword_list(v, true)}
          v -> maybe_to_keyword_list(v, true)
        end)

      object when is_list(object) ->
        Enum.filter(object, fn
          {k, v} -> {k, maybe_to_keyword_list(v, true)}
          v -> maybe_to_keyword_list(v, true)
        end)

      object ->
        object
    end
  end

  defp maybe_keyword_new(object) do
    if Enumerable.impl_for(object),
      do:
        Keyword.new(object, fn
          {key, val} when is_atom(key) ->
            {key, val}

          {key, val} when is_binary(key) ->
            case Types.maybe_to_atom!(key) do
              nil ->
                warn(key, "Discarding item with non-atom key")
                {:__item_discarded__, true}

              key ->
                {key, val}
            end

          other ->
            warn(other, "Discarding item that isn't a key/value pair")
            {:__item_discarded__, true}
        end),
      else: object
  rescue
    e ->
      warn(e)
      debug(__STACKTRACE__)
      object
  end

  @doc "Recursively converts all nested structs to maps."
  def nested_structs_to_maps(struct = %type{}) when type != DateTime,
    do: struct_to_map(struct) |> nested_structs_to_maps()

  def nested_structs_to_maps(enum) when is_map(enum) or is_list(enum) do
    if is_map(enum) or Keyword.keyword?(enum) do
      enum
      |> Enum.map(fn {k, v} -> {k, nested_structs_to_maps(v)} end)
      |> Enum.into(%{})
    else
      enum
    end
  end

  def nested_structs_to_maps(v), do: v

  def maybe_merge_to_struct(first, precedence) when is_struct(first),
    do: struct(first, maybe_from_struct(precedence))

  def maybe_merge_to_struct(%{} = first, precedence) do
    merged = merge_structs_as_map(first, precedence)

    # |> debug()

    case Bonfire.Common.Types.object_type(first) ||
           Bonfire.Common.Types.object_type(precedence) do
      type when is_atom(type) and not is_nil(type) ->
        if Types.defines_struct?(type) do
          debug("schema is available in the compiled app :-)")
          struct(type, merged)
        else
          debug(type, "schema doesn't exist in the compiled app")
          merged
        end

      other ->
        debug(other, "unknown type")
        merged
    end
  end

  def maybe_merge_to_struct(nil, precedence), do: precedence
  def maybe_merge_to_struct(first, nil), do: first

  def merge_structs_as_map(%{__typename: type} = target, merge)
      when not is_struct(target) and not is_struct(merge),
      do:
        Map.merge(target, merge)
        |> Map.put(:__typename, type)

  def merge_structs_as_map(target, merge)
      when is_struct(target) or is_struct(merge),
      do:
        merge_structs_as_map(
          maybe_from_struct(target),
          maybe_from_struct(merge)
        )

  def merge_structs_as_map(target, merge) when is_map(target) and is_map(merge),
    do: Map.merge(target, merge)

  @doc "Recursively filters nil values from a map"
  def map_filter_empty(data) when is_map(data) and not is_struct(data) do
    Enum.map(data, &map_filter_empty/1)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  def map_filter_empty({k, v}) do
    {k, map_filter_empty(v)}
  end

  def map_filter_empty(v) do
    filter_empty(v, nil)
  end

  @doc """
  Takes a map or keyword list, and returns a map with any atom keys converted to string keys. It can optionally do so recursively. 
  """
  def stringify_keys(map, recursive \\ false)
  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(object, true) when is_map(object) or is_list(object) do
    object
    |> maybe_to_map()
    |> Enum.map(fn {k, v} ->
      {
        Types.maybe_to_string(k),
        stringify_keys(v)
      }
    end)
    |> Enum.into(%{})
  end

  def stringify_keys(object, _) when is_map(object) or is_list(object) do
    object
    |> maybe_to_map()
    |> Enum.map(fn {k, v} -> {Types.maybe_to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Walk a list and stringify the keys of any map members
  # def stringify_keys([head | rest], recursive) do
  #   [stringify_keys(head, recursive) | stringify_keys(rest, recursive)]
  # end

  def stringify_keys(not_a_map, _recursive) do
    # warn(not_a_map, "Cannot stringify this object's keys")
    not_a_map
  end

  @doc "Takes a data structure and converts any keys in maps to (previously defined) atoms, recursively. By default any unknown string keys will be discarded. It can optionally also convert string values to known atoms as well."
  def input_to_atoms(
        data,
        opts \\ []
      )

  def input_to_atoms(data, opts) do
    opts =
      opts
      |> Keyword.put_new(:discard_unknown_keys, true)
      |> Keyword.put_new(:values, false)
      |> Keyword.put_new(:also_discard_unknown_nested_keys, true)
      # |> Keyword.put_new(:nested_discard_unknown, false)
      |> Keyword.put_new(:to_snake, false)
      |> Keyword.put_new(:values_to_integers, false)

    input_to_atoms(
      data,
      opts[:discard_unknown_keys],
      opts[:values],
      opts[:also_discard_unknown_nested_keys],
      false,
      opts[:to_snake],
      opts[:values_to_integers]
    )
  end

  def naughty_to_atoms!(data, _opts \\ []) do
    debug(
      data,
      "WARNING: only do this with enums who's keys are defined in the code (not user generated or coming from an HTTP request or socket, etc) !"
    )

    input_to_atoms(data, false, false, false, true, false, false)
  end

  defp input_to_atoms(
         enum,
         discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       )

  defp input_to_atoms(data, _, _, _, _, _, _) when is_struct(data) do
    # skip structs
    data
  end

  defp input_to_atoms(
         %{} = data,
         true = discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       ) do
    # turn any keys into atoms (if such atoms already exist) and discard the rest
    :maps.filter(
      fn k, _v -> is_atom(k) end,
      data
      |> Map.drop(["_csrf_token", "_persistent_id"])
      |> Map.new(fn {k, v} ->
        {
          Types.maybe_to_atom_or_module(k, force, to_snake),
          if(also_discard_unknown_nested_keys,
            do:
              input_to_atoms(
                v,
                true,
                including_values,
                true,
                force,
                to_snake,
                values_to_integers
              ),
            else:
              input_to_atoms(
                v,
                false,
                including_values,
                false,
                force,
                to_snake,
                values_to_integers
              )
          )
        }
      end)
    )
  end

  defp input_to_atoms(
         %{} = data,
         false = discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       ) do
    data
    |> Map.drop(["_csrf_token"])
    |> Map.new(fn {k, v} ->
      {
        Types.maybe_to_atom_or_module(k, force, to_snake) || k,
        input_to_atoms(
          v,
          false,
          including_values,
          also_discard_unknown_nested_keys,
          force,
          to_snake,
          values_to_integers
        )
      }
    end)
  end

  defp input_to_atoms(
         list,
         true = discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       )
       when is_list(list) do
    if Keyword.keyword?(list) and list != [] do
      Map.new(list)
      |> input_to_atoms(
        true,
        including_values,
        also_discard_unknown_nested_keys,
        force,
        to_snake,
        values_to_integers
      )
    else
      Enum.map(
        list,
        &input_to_atoms(
          &1,
          false,
          including_values,
          also_discard_unknown_nested_keys,
          force,
          to_snake,
          values_to_integers
        )
      )
    end
  end

  defp input_to_atoms(
         list,
         _false = discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       )
       when is_list(list) do
    if Keyword.keyword?(list) and list != [] do
      Map.new(list)
      |> input_to_atoms(
        false,
        including_values,
        also_discard_unknown_nested_keys,
        force,
        to_snake,
        values_to_integers
      )
    else
      Enum.map(
        list,
        &input_to_atoms(
          &1,
          false,
          including_values,
          also_discard_unknown_nested_keys,
          force,
          to_snake,
          values_to_integers
        )
      )
    end
  end

  # defp input_to_atoms(
  #       {key, val},
  #       discard_unknown_keys,
  #       including_values,
  #       also_discard_unknown_nested_keys,
  #       force,
  #       to_snake,
  #       values_to_integers
  #     )

  defp input_to_atoms(
         other,
         discard_unknown_keys,
         including_values,
         also_discard_unknown_nested_keys,
         force,
         to_snake,
         values_to_integers
       ),
       do:
         input_to_value(
           other,
           discard_unknown_keys,
           including_values,
           also_discard_unknown_nested_keys,
           force,
           to_snake,
           values_to_integers
         )

  # support truthy/falsy values
  def input_to_value("nil", _, true = _including_values, _, _, _, _), do: nil
  def input_to_value("false", _, true = _including_values, _, _, _, _), do: false
  def input_to_value("true", _, true = _including_values, _, _, _, _), do: true

  def input_to_value(
        v,
        _,
        true = _including_values,
        _,
        force,
        _to_snake,
        true = _values_to_integers
      )
      when is_binary(v) do
    Types.maybe_to_integer(v, nil) || Types.maybe_to_module(v, force) || Types.maybe_to_atom(v) ||
      v
  end

  def input_to_value(v, _, true = _including_values, _, force, _to_snake, _values_to_integers)
      when is_binary(v) do
    Types.maybe_to_module(v, force) || Types.maybe_to_atom(v) || v
  end

  def input_to_value(v, _, _, _, _, _, true = _values_to_integers) when is_binary(v),
    do: Types.maybe_to_integer(v, nil) || v

  def input_to_value(v, _, _, _, _, _, _), do: v

  @doc "Takes a data structure and recursively converts any known keys to atoms and then tries to recursively convert any maps to structs, using some hints in the data (eg. `__type` or `index_type` fields)."
  def maybe_to_structs(v, opts \\ [])
  def maybe_to_structs(v, _opts) when is_struct(v), do: v

  def maybe_to_structs(v, opts),
    do: v |> input_to_atoms(opts) |> maybe_to_structs_recurse()

  defp maybe_to_structs_recurse(data, parent_id \\ nil)

  defp maybe_to_structs_recurse(%{index_type: type} = data, parent_id) do
    data
    |> Map.new(fn {k, v} ->
      {k, maybe_to_structs_recurse(v, Utils.e(data, :id, nil))}
    end)
    |> maybe_add_mixin_id(parent_id)
    |> maybe_to_struct(type)
  end

  defp maybe_to_structs_recurse(%{} = data, _parent_id) do
    Map.new(data, fn {k, v} ->
      {k, maybe_to_structs_recurse(v, Utils.e(data, :id, nil))}
    end)
  end

  defp maybe_to_structs_recurse(v, _), do: v

  defp maybe_add_mixin_id(%{id: id} = data, _parent_id) when not is_nil(id),
    do: data

  defp maybe_add_mixin_id(data, parent_id) when not is_nil(parent_id),
    do: Map.merge(data, %{id: parent_id})

  defp maybe_add_mixin_id(data, _parent_id), do: data

  @doc "Takes a data structure and tries to convert it to a struct, using some hints in the data (eg. `__type` or `index_type` fields) or a manually-provided type."
  def maybe_to_struct(obj, type \\ nil)

  def maybe_to_struct(%{__struct__: struct_type} = obj, target_type)
      when target_type == struct_type,
      do: obj

  def maybe_to_struct(obj, type) when is_struct(obj) do
    maybe_from_struct(obj) |> maybe_to_struct(type)
  end

  def maybe_to_struct(obj, type) when is_binary(type) do
    case Types.maybe_to_module(type) do
      module when is_atom(module) -> maybe_to_struct(obj, module)
      _ -> obj
    end
  end

  def maybe_to_struct(obj, type) when is_atom(type) do
    # if module_enabled?(module) and module_enabled?(Mappable) do
    #   Mappable.to_struct(obj, module)
    # else
    if module_enabled?(type),
      do: struct(type, obj),
      else: obj

    # end
  end

  # for search results
  def maybe_to_struct(%{index_type: type} = obj, _type),
    do: maybe_to_struct(obj, type)

  # for graphql queries
  def maybe_to_struct(%{__typename: type} = obj, _type),
    do: maybe_to_struct(obj, type)

  def maybe_to_struct(obj, _type), do: obj

  # MIT licensed function by Kum Sackey
  def struct_from_map(a_map, as: a_struct) do
    keys = Map.keys(Map.delete(a_struct, :__struct__))
    # Process map, checking for both string / atom keys
    for(
      key <- keys,
      into: %{},
      do: {key, Map.get(a_map, key) || Map.get(a_map, to_string(key))}
    )
    |> Map.merge(a_struct, ...)
  end

  @doc "Counts the number of items in an enumerable that satisfy the given function."
  def count_where(collection, function \\ &is_nil/1) do
    Enum.reduce(collection, 0, fn item, count ->
      if function.(item), do: count + 1, else: count
    end)
  end

  @doc """
  Like `Enum.group_by/3`, except children are required to be unique (will throw
  otherwise!) and the resulting map does not wrap each item in a list
  """
  def group([], fun) when is_function(fun, 1), do: %{}

  def group(list, fun)
      when is_list(list) and is_function(fun, 1),
      do: group(list, %{}, fun)

  defp group([x | xs], acc, fun),
    do: group(xs, group_item(fun.(x), x, acc), fun)

  defp group([], acc, _), do: acc

  defp group_item(key, value, acc)
       when not is_map_key(acc, key),
       do: Map.put(acc, key, value)

  def group_map([], fun) when is_function(fun, 1), do: %{}

  def group_map(list, fun)
      when is_list(list) and is_function(fun, 1),
      do: group_map(list, %{}, fun)

  defp group_map([x | xs], acc, fun),
    do: group_map(xs, group_map_item(fun.(x), acc), fun)

  defp group_map([], acc, _), do: acc

  defp group_map_item({key, value}, acc)
       when not is_map_key(acc, key),
       do: Map.put(acc, key, value)

  @doc "Applies a function from one of Elixir's `Map`, `Keyword`, or `List` modules depending on the type of the given enumerable."
  def fun(map, fun, args \\ [])

  def fun(map, fun, args) when is_map(map) do
    Utils.maybe_apply(Map, fun, [map] ++ List.wrap(args))
  end

  def fun(list, fun, args) when is_list(list) do
    if Keyword.keyword?(list) do
      Utils.maybe_apply(Keyword, fun, [list] ++ List.wrap(args))
    else
      Utils.maybe_apply(List, fun, [list] ++ List.wrap(args))
    end
  end

  defp maybe_fun(module, enum, fun, args) when is_map(enum) do
    args = [enum] ++ List.wrap(args)

    if function_exported?(module, fun, length(args)),
      do: Utils.maybe_apply(module, fun, args),
      else: Utils.maybe_apply(Enum, fun, args)
  end
end
