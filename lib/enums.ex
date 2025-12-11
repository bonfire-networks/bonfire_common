# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Enums do
  @moduledoc "Extra functions to manipulate enumerables, basically an extension of `Enum`"

  use Arrows
  import Untangle
  use Bonfire.Common.E
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Extend
  alias Ecto.Changeset
  # alias Bonfire.Common
  use Bonfire.Common.Config
  # alias Bonfire.Common.Text
  alias Bonfire.Common.Types
  alias Bonfire.Common.Utils

  @compile {:inline, group: 3}

  @doc """
  Applies a function from one of Elixir's `Map`, `Keyword`, `List`, `Tuple` modules depending on the type of the given enumerable, or using a function in `Enum` if no specific one is defined.

  ## Examples

      > Bonfire.Common.Enums.fun(%{a: 1, b: 2}, :values)
      # runs `Map.values/1`
      [2, 1]

      iex> Bonfire.Common.Enums.fun([a: 1, b: 2], :values)
      # runs `Keyword.values/1`
      [1, 2]

      iex> Bonfire.Common.Enums.fun([1, 2, 3], :first)
      # runs `List.first/1`
      1

      iex> Bonfire.Common.Enums.fun({1, 2}, :sum)
      # runs `Tuple.sum/1`
      3

      iex> Bonfire.Common.Enums.fun({1, 2}, :last)
      # runs `List.last/1` after converting the tuple to a list
      2

      iex> Bonfire.Common.Enums.fun([1, 2, 3], :sum)
      # runs `Enum.sum/1` because there's no `List.sum/1`
      6

  """
  def fun(map, fun, args \\ [])

  def fun(map, fun, args) when is_map(map) do
    args = [map] ++ List.wrap(args)

    Utils.maybe_apply(Map, fun, args, fallback_fun: fn -> Utils.maybe_apply(Enum, fun, args) end)
  end

  def fun(list, fun, args) when is_list(list) do
    args = [list] ++ List.wrap(args)

    if Keyword.keyword?(list) do
      Utils.maybe_apply(Keyword, fun, args,
        fallback_fun: fn -> Utils.maybe_apply(Enum, fun, args) end
      )
    else
      Utils.maybe_apply(List, fun, args,
        fallback_fun: fn -> Utils.maybe_apply(Enum, fun, args) end
      )
    end
  end

  def fun(tuple, func, args) when is_tuple(tuple) do
    # Note: tuples aren't technically enumerables, but included for convenience
    Utils.maybe_apply(Tuple, func, [tuple] ++ List.wrap(args),
      fallback_fun: fn ->
        fun(Tuple.to_list(tuple), func, args)
      end
    )
  end

  @doc """
  Extracts a binary ID from various data structures, such as a map containing the key :id or "id", a changeset, or a tuple containing the atom :id.
  """
  def id(id) when is_binary(id), do: id
  def id(%{id: id}), do: id
  def id(%Changeset{} = cs), do: id(Changeset.get_field(cs, :id))
  def id({:id, id}), do: id
  def id(%{"id" => id}), do: id
  def id(%{value: value}), do: id(value)
  def id(%{"value" => value}), do: id(value)
  def id(%{pointer: %{id: id}}), do: id

  # TODO: avoid logging each when recursing
  def id(ids) when is_list(ids),
    do: ids |> maybe_flatten() |> Enum.map(&id/1) |> filter_empty(nil)

  def id({:ok, other}), do: id(other)

  def id(id) do
    e = "Expected an ID (or an object with one)"
    # throw {:error, e}
    debug(id, e, trace_skip: 1)
    nil
  end

  @doc """
  Extracts the IDs from a list of maps, changesets, or other data structures and returns a list of these IDs.

        iex> ids([%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}])
        [1, 2]

        iex> ids(%{id: 3})
        [3]
  """
  def ids(objects), do: id(objects) |> List.wrap()

  @doc "Takes an enumerable object and converts it to a map. If it is not an enumerable, a map is created with the data under a fallback key (`:data` by default)."
  def map_new(data, fallback_key \\ :data) do
    if Enumerable.impl_for(data),
      do: Map.new(data),
      else: Map.put(%{}, fallback_key, data)
  end

  @doc """
  Updates a nested map using a list of keys and a value to set. It returns a new map with the updated value at the specified location.

  ## Examples

      iex> map_put_in(%{}, [:a, :b, :c], 3)
      %{a: %{b: %{c: 3}}}

  ## Parameters
    * `root` - The initial map (can be an empty map or a populated one).
    * `keys` - A list of keys specifying the path to the value.
    * `value` - The value to set at the specified location.
  """
  def map_put_in(root \\ %{}, keys, value) do
    # root = %{} or non empty map
    # keys = [:a, :b, :c]
    # value = 3
    put_in(root, access_keys(keys, %{}), value)
  end

  def get_in_access_keys!(%schema{} = map, keys, last_fallback) when is_map(map) do
    if Extend.module_behaviour?(schema, Access) do
      case try_access(fn -> get_in(map, keys) end) do
        nil ->
          last_fallback

        BadMapError ->
          last_fallback

        FunctionClauseError ->
          last_fallback

        UndefinedFunctionError ->
          get_in(map, access_keys(keys, last_fallback))

        val ->
          val
          |> debug("with struct Access")
      end
    else
      get_in(map, access_keys(keys, last_fallback))
    end
  end

  def get_in_access_keys!(map, keys, last_fallback) when is_map(map) do
    get_in(map, access_keys(keys, last_fallback))
  end

  def get_in_access_keys(map, keys, last_fallback) do
    try_access(fn -> get_in_access_keys!(map, keys, last_fallback) end, last_fallback)
  end

  defp try_access(fun, error_fallback \\ nil) do
    fun.()
  rescue
    e in BadMapError ->
      # eg. an element in the tree is not a map
      warn(e)
      error_fallback || BadMapError

    e in FunctionClauseError ->
      warn(e)
      error_fallback || FunctionClauseError

    e in UndefinedFunctionError ->
      # eg. function MyStruct.fetch/2 is undefined (does not implement the Access behaviour)
      warn(e)
      error_fallback || UndefinedFunctionError
  end

  def access_keys(keys, last_fallback \\ nil)

  def access_keys(key, last_fallback) when not is_list(key), do: access_keys([key], last_fallback)

  def access_keys(keys, %{}) do
    Enum.map(keys, &Access.key(&1, %{}))
  end

  def access_keys(keys, last_fallback) do
    {last, keys} = List.pop_at(keys, -1)

    access_keys(keys, %{}) ++
      [Access.key(last, last_fallback)]
  end

  @doc """
  Attempts to retrieve a value from a data structure (map, keyword list, or list) by key, with flexible matching and fallback support.

  - For maps: If given an atom key, tries the atom, then stringified versions.
  For string keys, tries the string, then camelCase, then an atomized version (if the atom exists).
  - For keyword lists: Only atom keys are supported.
  - For lists of maps/structs: Returns a list of values for each element, applying the same logic to each.
  - For a list of keys: Returns a list of values for each key, applying the same logic to each.

  Returns the fallback if no value is found or if the value is considered empty (nil, empty list, empty map, etc).

  ## Examples

      iex> get_eager(%{foo: 1}, :foo, :none)
      1
      iex> get_eager(%{foo: 1}, "foo", :none)
      1
      iex> get_eager(%{"bar" => 2, foo: 1}, "bar", :none)
      2
      iex> get_eager(%{"bar" => 2, foo: 1}, :bar, :none)
      2
      iex> get_eager(%{"barBaz" => 3, foo: 1}, :bar_baz, :none)
      3
      iex> get_eager(%{"barBaz" => 3, foo: 1}, "bar_baz", :none)
      3
      iex> get_eager(%{"foo" => 1}, :foo, :none)
      1
      iex> get_eager(%{"foo" => 1}, :bar, :none)
      :none
      iex> get_eager([a: 1, b: 2], :b, :none)
      2
      iex> get_eager([%{id: 1, foo: 2}, %{id: 2, foo: 3}], :foo, :none)
      [2, 3]
      iex> get_eager([%{id: 1, foo: 2}, %{id: 2}], :foo, :none)
      [2]
      iex> get_eager([%{foo: 1}, %{bar: 2}], :foo, :none)
      [1]
      iex> get_eager([%{foo: 1}, %{bar: 2}], :baz, :fallback)
      :fallback
      iex> get_eager(%{foo: 1, bar: 2}, [:foo, :bar], :none)
      [1, 2]
      iex> get_eager([%{foo: 1}, %{bar: 2}], [:foo, :bar], :none) |> List.flatten()
      [1, 2]
      iex> get_eager(%{}, :foo, :fallback)
      :fallback
      iex> get_eager(nil, :foo, :fallback)
      :fallback
      iex> get_eager([a: 1, b: nil], :b, :fallback)
      :fallback

  """
  def get_eager(map, key, fallback \\ nil)

  def get_eager(map, key, fallback) when is_map(map) and is_atom(key) do
    case maybe_get(map, key, :empty) do
      :empty -> do_get_eager_with_strings(map, Atom.to_string(key), fallback)
      val -> val
    end
    |> magic_filter_empty(map, key, fallback)
  end

  def get_eager(map, key, fallback) when is_map(map) and is_binary(key) do
    # Attempt getting a value out of a map by stringified key, or try with atom key (if it's an existing atom), or return a fallback
    case do_get_eager_with_strings(map, key, :empty) do
      :empty ->
        maybe_get(map, Types.maybe_to_atom(key), fallback)

      val ->
        val
    end
    |> magic_filter_empty(map, key, fallback)
  end

  def get_eager(enum, keys, fallback) when is_list(keys) do
    # Get one or more matches for each key in list
    Enum.map(keys, &get_eager(enum, &1, nil))
    |> filter_empty(fallback)
  end

  def get_eager(enum, key, fallback) when is_list(enum) do
    if Keyword.keyword?(enum) do
      # keyword can't have string keys, so do a normal get
      maybe_get(enum, key, fallback)
      |> magic_filter_empty(enum, key, fallback)
    else
      # Get one or more matches for each element in list
      Enum.map(enum, &get_eager(&1, key, nil))
      |> filter_empty(fallback)
    end
  end

  def get_eager(enum, key, fallback) do
    # any other enumerable, try a normal get
    maybe_get(enum, key, fallback)
    |> magic_filter_empty(enum, key, fallback)
  end

  defp do_get_eager_with_strings(map, key, fallback) when is_map(map) and is_binary(key) do
    # Attempt getting a value out of a map by string key, or try with key in camelCase 
    case maybe_get(map, key, :empty) do
      :empty ->
        maybe_get(map, Recase.to_camel(key), fallback)

      val ->
        val
    end
  end

  @doc """
  Attempts to retrieve a value from a map or keyword list by key, returning the fallback if not found.

  - For maps: Uses `Map.get/3`.
  - For keyword lists: Uses `Keyword.get/3`.
  - For other lists: Returns the fallback and logs a warning.
  - For all other types: Always returns the fallback.

  ## Examples

      iex> import Bonfire.Common.Enums
      iex> maybe_get(%{foo: 1}, :foo, :none)
      1
      iex> maybe_get(%{"foo" => 2}, "foo", :none)
      2
      iex> maybe_get([a: 1, b: 2], :b, :none)
      2
      iex> maybe_get([{:a, 1}, {:b, nil}], :b, :none)
      nil
      iex> maybe_get([1, 2, 3], :foo, :fallback)
      :fallback
      iex> maybe_get(nil, :foo, :fallback)
      :fallback
      iex> maybe_get(%{}, :foo, :fallback)
      :fallback

  """
  def maybe_get(_, _, fallback \\ nil)

  def maybe_get(%{} = map, key, fallback),
    do: Map.get(map, key, fallback)

  def maybe_get(enum, key, fallback) when is_list(enum) do
    if Keyword.keyword?(enum) do
      Keyword.get(enum, key, fallback)
    else
      warn(enum, "maybe_get expects a map or keyword list")
      fallback
    end
  end

  def maybe_get(_, _, fallback), do: fallback

  def first!(list) when is_list(list) do
    case List.first(list, :none) do
      :none ->
        debug(list)
        raise ArgumentError, message: "List is empty"

      val ->
        val
    end
  end

  def first!(tuple) when is_tuple(tuple) do
    elem(tuple, 0)
  end

  def first!(enum) do
    case Enum.at(enum, 0, :none) do
      :none ->
        debug(enum)
        raise ArgumentError, message: "Enumerable is empty"

      val ->
        val
    end
  end

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
       when is_atom(key) do
    if Config.env() == :dev && Config.get(:e_auto_preload, false) do
      warn(
        "The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the original query or somewhere where it won't trigger n+1 performance issues..."
      )

      repo().maybe_preload(map, key)
      |> Map.get(key, fallback)
      |> filter_empty(fallback)
    else
      debug("`e` requested #{inspect(key)} on #{schema} but that assoc was not preloaded")

      fallback
    end
  end

  defp magic_filter_empty(val, _, _, fallback), do: filter_empty(val, fallback)

  @doc "Takes a value and a fallback value. If the value is empty (e.g. an empty map, a non-loaded association, an empty list, an empty string, or nil), the fallback value is returned."
  def filter_empty(val, fallback)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback

  def filter_empty(%Needle.Pointer{deleted_at: del}, fallback) when not is_nil(del),
    do: fallback

  def filter_empty([], fallback), do: fallback
  def filter_empty(map, fallback) when map == %{}, do: fallback
  def filter_empty("", fallback), do: fallback
  def filter_empty(nil, fallback), do: fallback
  def filter_empty({:error, _}, fallback), do: fallback

  def filter_empty(enum, fallback) when is_list(enum),
    do:
      enum
      |> filter_empty_enum(false)
      |> re_filter_empty(fallback)

  def filter_empty(enum, fallback) when is_map(enum) and not is_struct(enum),
    do:
      enum
      # |> debug()
      |> filter_empty_enum(false)
      |> Enum.into(%{})
      |> re_filter_empty(fallback)

  def filter_empty(val, _fallback), do: val

  @doc """
  Filters empty values from an enumerable. When given key-value pairs, it can either check keys as well, or only filter based on values.

  ## Examples

      iex> filter_empty_enum([1, nil, 2, "", 3, [], 4, %{}], true)
      [1, 2, 3, 4]

      iex> filter_empty_enum([{:a, 1}, {:b, nil}, {:c, ""}, {:d, 2}], true)
      [a: 1, d: 2]

      iex> filter_empty_enum([{:a, 1}, {:b, nil}, {:c, ""}, {:d, 2}], false)
      [{:a, 1}, {:d, 2}]

      iex> filter_empty_enum([{nil, 1}, {false, nil}, {:b, []}, {:c, 3}], true)
      [c: 3]

      iex> filter_empty_enum([{nil, 1}, {false, nil}, {:b, []}, {:c, 3}], false)
      [{nil, 1}, {:c, 3}]

  """
  def filter_empty_enum(enum, check_keys? \\ false)

  def filter_empty_enum(enum, check_keys?) when is_struct(enum),
    do: struct_to_map(enum) |> filter_empty_enum(check_keys?)

  def filter_empty_enum(enum, check_keys?) when is_map(enum) or is_list(enum) do
    Enum.reduce(enum, [], fn
      {key, val}, acc when check_keys? == false ->
        filtered_val = filter_empty(val, nil)
        if filtered_val == nil, do: acc, else: [{key, filtered_val} | acc]

      {key, val}, acc ->
        filtered_key = filter_empty(key, nil)
        filtered_val = filter_empty(val, nil)

        cond do
          filtered_key == nil or filtered_val == nil -> acc
          true -> [{filtered_key, filtered_val} | acc]
        end

      val, acc ->
        filtered_val = filter_empty(val, nil)
        if filtered_val == nil, do: acc, else: [filtered_val | acc]
    end)
    |> Enum.reverse()
  end

  defp re_filter_empty([], fallback), do: fallback
  defp re_filter_empty(map, fallback) when is_map(map) and map == %{}, do: fallback
  defp re_filter_empty(nil, fallback), do: fallback
  # defp re_filter_empty([val], nil), do: val
  defp re_filter_empty(val, _fallback), do: val

  def filter_empty(%{key: nil}, fallback, _key) do
    fallback
  end

  def filter_empty(enum, fallback, key) when is_atom(key) or is_binary(key) do
    case get_eager(enum, key) do
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
  def maybe_elem(tuple, index, _fallback) when is_tuple(tuple), do: elem(tuple, index)
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
  Checks a map for a value with provided key. If it already exists, the existing value is retained, but if not set or nil, then it is set to the provided default.
  """
  def map_put_default(map, key, default) do
    Map.update(map, key, default, fn
      nil -> default
      existing_value -> existing_value
    end)
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
  Updates a `Map` or `Keyword` with the given `key` and `value`, but only if the `value` is not `nil`, an empty list or an empty string.
  """
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value) when is_map(map), do: Map.put(map, key, value)
  def maybe_put(list, key, value) when is_list(list), do: Keyword.put(list, key, value)

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

  @doc "Deep merges a list of maps or keyword lists into a single map."
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

  @doc """
  Merges two maps while keeping only the keys that exist in the first map.
  """
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
  def maybe_flatten(map) when is_map(map), do: flatten_map(map)
  def maybe_flatten(other), do: other

  @doc """
  Takes a list and recursively flattens it by recursively flattening the head and tail of the list
  """
  def flatter(list) when is_list(list), do: list |> do_flatter() |> maybe_flatten()
  def flatter(map) when is_map(map), do: flatten_map(map, true)

  defp do_flatter([element | nil]), do: do_flatter(element)
  defp do_flatter([head | tail]), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter([]), do: []
  defp do_flatter({head, tail}), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter(element), do: element

  defp flatten_map(map, recursive \\ false) when is_map(map) do
    map
    |> Map.to_list()
    |> do_flatten([], recursive)
    |> Map.new()
  end

  defp do_flatten([], acc, _), do: acc

  defp do_flatten([{_k, v} = kv | rest], acc, recursive) when is_struct(v) do
    do_flatten(rest, [kv | acc], recursive)
  end

  defp do_flatten([{_k, v} | rest], acc, true) when is_map(v) do
    v = Map.to_list(v)
    flattened_subtree = do_flatten(v, acc, true)
    do_flatten(flattened_subtree ++ rest, acc, true)
  end

  defp do_flatten([{_k, v} | rest], acc, _) when is_map(v) do
    v = Map.to_list(v)
    do_flatten(v ++ rest, acc, false)
  end

  defp do_flatten([kv | rest], acc, recursive) do
    do_flatten(rest, [kv | acc], recursive)
  end

  @doc "If given a struct, returns a map representation of it"
  def struct_to_map(other, recursive \\ false)

  def struct_to_map(struct = %{__struct__: type}, false) do
    Map.from_struct(struct)
    |> Map.drop([:__meta__])
    |> Map.put_new(:__typename, type)
    |> map_filter_empty()
  end

  def struct_to_map(struct = %{__struct__: _type}, true) do
    struct_to_map(struct, false)
    |> Enum.map(&struct_to_map(&1, true))
    |> Map.new()
  end

  def struct_to_map(data, true) when is_map(data) do
    struct_to_map(data, false)
    |> Enum.map(&struct_to_map(&1, true))
    |> Map.new()
  end

  def struct_to_map(data, true) do
    if Enumerable.impl_for(data) do
      struct_to_map(data, false)
      |> Enum.map(fn
        {k, v} -> {k, struct_to_map(v, true)}
        v -> struct_to_map(v, true)
      end)
    else
      data
    end
  end

  def struct_to_map(other, _false), do: other

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

  def maybe_to_map(date = %struct{}, true) when struct in [Date, DateTime],
    do: to_string(date)

  def maybe_to_map(struct = %{__struct__: _}, true),
    do: struct_to_map(struct) |> maybe_to_map(true)

  def maybe_to_map({a, b}, true), do: %{a => maybe_to_map(b, true)}

  def maybe_to_map(data, true) do
    if Enumerable.impl_for(data) do
      data
      |> Enum.map(fn
        {a, b} ->
          {a, maybe_to_map(b, true)}

        other ->
          debug(other, "Expected a tuple")
          throw(:not_tuples)
      end)
      |> Map.new()
    else
      data
    end
  catch
    :not_tuples ->
      data
      |> Enum.map(fn
        other -> maybe_to_map(other, true)
      end)
  end

  @doc """
  Returns a keyword list representation of the input object. If the second argument is `true`, the function will recursively convert nested data structures to keyword lists as well.
  Note: make sure that all keys are atoms, i.e. using `input_to_atoms` first, otherwise the enumerable(s) containing a string key won't be converted.
  """
  def maybe_to_keyword_list(obj, recursive \\ false, force_top_level \\ true)

  def maybe_to_keyword_list(obj, _, _)
      when not is_map(obj) and not is_list(obj),
      do: obj

  def maybe_to_keyword_list(object, false = _not_recursive, force_top_level) do
    maybe_keyword_new(object, force_top_level)
  end

  def maybe_to_keyword_list(obj, recursive_mode, force_top_level) do
    maybe_to_keyword_list_recurse(obj, recursive_mode, force_top_level)
  end

  defp maybe_to_keyword_list_recurse(object, recursive_mode, force_top_level) do
    force_recursive_levels? = recursive_mode == :force

    case maybe_keyword_new(object, force_top_level) do
      object when is_map(object) ->
        debug(object, "not able to turn into keyword list, but still try with the children")

        Map.new(object, fn
          {k, v} -> {k, maybe_to_keyword_list(v, recursive_mode, force_recursive_levels?)}
          v -> maybe_to_keyword_list(v, recursive_mode, force_recursive_levels?)
        end)

      object when is_list(object) ->
        if Keyword.keyword?(object) do
          Keyword.new(object, fn
            {k, v} -> {k, maybe_to_keyword_list(v, recursive_mode, force_recursive_levels?)}
            v -> maybe_to_keyword_list(v, recursive_mode, force_recursive_levels?)
          end)
        else
          object
          |> debug("is a list but not a keyword list, will try to convert elements")
          |> Enum.map(fn v ->
            maybe_to_keyword_list(v, recursive_mode, force_recursive_levels?)
          end)
        end

      object ->
        object
    end
  end

  defp maybe_keyword_new(object, force?) do
    if Enumerable.impl_for(object) do
      Keyword.new(object, fn
        {key, val} when is_atom(key) ->
          {key, val}

        {key, val} when is_binary(key) ->
          case Types.maybe_to_atom!(key) do
            nil ->
              if force? do
                warn(val, "discarding item with non-atom key #{inspect(key)}")
                {:__item_discarded__, true}
              else
                warn(val, "will use a map due to an item with non-atom key #{inspect(key)}")
                throw(:__item_discarded__)
              end

            key ->
              {key, val}
          end

        other ->
          if force? do
            warn(other, "discarding item that isn't a key/value pair")
            {:__not_kv__, true}
          else
            warn(other, "will return item as-is because it isn't a key/value pair")
            throw(:__not_kv__)
          end
      end)
    else
      object
      |> debug("will return item as-is because it isn't an enumerable")
    end
  rescue
    e ->
      warn(e)
      debug(__STACKTRACE__)
      object
  catch
    :__item_discarded__ ->
      Map.new(object)

    :__not_kv__ ->
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

  def merge_to_struct(module \\ nil, first, precedence)

  def merge_to_struct(module, first, precedence) when not is_struct(first),
    do: merge_to_struct(nil, struct(module, first), precedence)

  def merge_to_struct(_, first, precedence) when is_struct(first),
    do: struct(first, struct_to_map(precedence))

  def maybe_merge_to_struct(first, precedence) when is_struct(first),
    do: struct(first, struct_to_map(precedence))

  def maybe_merge_to_struct(%{} = first, precedence) do
    merged = merge_structs_as_map(first, precedence)

    # |> debug()

    case Bonfire.Common.Types.object_type(first, only_schemas: true) ||
           Bonfire.Common.Types.object_type(precedence, only_schemas: true) do
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
          struct_to_map(target),
          struct_to_map(merge)
        )

  def merge_structs_as_map(target, merge) when is_map(target) and is_map(merge),
    do: Map.merge(target, merge)

  @doc "Recursively filters nil values from a map"
  def map_filter_empty(data) when is_map(data) and not is_struct(data) do
    data
    # |> Enum.map(&map_filter_empty/1)
    |> Enum.reject(fn
      {_, nil} -> true
      {_, %Ecto.Association.NotLoaded{}} -> true
      _ -> false
    end)
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
         true = _discard_unknown_keys,
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
         false = _discard_unknown_keys,
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
         true = _discard_unknown_keys,
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
         false = _discard_unknown_keys,
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

  @doc """
  Converts input to value based on the provided options.

  ## Examples

      iex> input_to_value("42", false, true, nil, true, nil, true)
      42

      iex> input_to_value("Bonfire.Common", false, true, nil, true, nil, false)
      Bonfire.Common

      iex> input_to_value("bonfire_common", false, true, nil, true, nil, false)
      :bonfire_common

      iex> input_to_value("unknown_example_string", false, true, nil, true, nil, false)
      "unknown_example_string"
  """
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

  @doc """
  Takes a data structure and recursively converts any known keys to atoms and then tries to
  recursively convert any maps to structs, using hints in the data (eg. `__type` or `index_type` fields) or related schemas (eg. mixins).

  NOTE: you may want to call `input_to_atoms/2` on the data first if it contains string keys instead of atoms.

  ## Examples


      iex> # Nested maps with `index_type` or `__typename`
      iex> maybe_to_structs(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     __typename: Bonfire.Data.Identity.Character,
      ...>     id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }
      iex> # Nested maps with `index_type` on top-level and nested mixin with no hint of type (gets inferred from the parent schema)
      iex> maybe_to_structs(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }

      iex> # Nested maps with `index_type` on top-level and nested mixin with no ID (gets inferred from the parent schema)
      iex> maybe_to_structs(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     __typename: Bonfire.Data.Identity.Character,
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }

      iex> # Nested maps with `index_type` on top-level and nested mixin with no hint of type or ID (both get inferred from the parent schema)
      iex> maybe_to_structs(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }

      iex> # Nested maps with type override for the top level
      iex> maybe_to_structs(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     __typename: Bonfire.Data.Identity.Character,
      ...>     id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>     username: "test"
      ...>   }
      ...> }, Needle.Pointer)
      %Needle.Pointer{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }

      iex> # Struct with nested map with `__typename`
      iex> maybe_to_structs(%Bonfire.Data.Identity.User{
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     __typename: Bonfire.Data.Identity.Character,
      ...>     id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %Bonfire.Data.Identity.Character{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }
  """

  def maybe_to_structs(data, top_level_type \\ nil, parent_schema_throuple \\ nil)

  # Handle collections (lists, etc)
  def maybe_to_structs(list, top_level_type, parent_schema_throuple) when is_list(list) do
    Enum.map(list, &maybe_to_structs(&1, top_level_type, parent_schema_throuple))
  end

  # Handle maps (including those with type hints)
  def maybe_to_structs(%{} = data, top_level_type, parent_schema_throuple) do
    # infer mixins when recursing
    data = maybe_add_mixin(data, parent_schema_throuple)
    type = top_level_type || Types.maybe_to_module(schema_type(data))
    id = id(data)

    # First recursively process all nested values
    #  because can't enumerate a struct
    struct_to_map(data)
    |> Map.new(fn {k, v} ->
      #  passing current type as parent of next level
      {k, maybe_to_structs(v, nil, {type, id, k})}
    end)
    # Convert to struct if possible
    |> maybe_to_struct(type)
  end

  def maybe_to_structs(v, _, _), do: v

  @doc """
  Adds parent ID to map if it represents a mixin of the parent schema.
  """
  defp maybe_add_mixin(%{} = data, {parent_type, parent_id, assoc_key})
       when not is_nil(parent_type) do
    # debug(assoc_key, inspect(parent_type))

    if function_exported?(parent_type, :__schema__, 1) do
      if module =
           Bonfire.Common.Needles.Tables.maybe_assoc_mixin_module(assoc_key, parent_type) do
        data
        |> Map.put(:__typename, module)
        |> maybe_put(:id, parent_id)
      end
    end || data
  end

  defp maybe_add_mixin(data, _parent_schema_throuple), do: data

  @doc """
  Takes a data structure and tries to convert it to a struct, using the optional type provided or some hints in the data (eg. `__type` or `index_type` fields).

  NOTE: you may want to call `input_to_atoms/2` on the data first if it contains string keys instead of atoms.

  ## Examples

      iex> # Convert map with `index_type` to struct (and leave nested map alone, hint: use `maybe_to_structs/1` to also process nested data)
      iex> maybe_to_struct(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>   character: %{
      ...>     id: "01JB4E8T1H928QC6E1MP1XDZD8",
      ...>     username: "test"
      ...>   }
      ...> })
      %Bonfire.Data.Identity.User{
        id: "01JB4E8T1H928QC6E1MP1XDZD8",
        character: %{
          id: "01JB4E8T1H928QC6E1MP1XDZD8",
          username: "test"
        }
      }

      iex> # Map to a specific struct (ignores hints in data)
      iex> maybe_to_struct(%{
      ...>   index_type: "Bonfire.Data.Identity.User",
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8"
      ...> }, Bonfire.Data.Identity.Character)
      %Bonfire.Data.Identity.Character{
        id: "01JB4E8T1H928QC6E1MP1XDZD8"
      }

      iex> # Struct to a different struct
      iex> maybe_to_struct(%Bonfire.Data.Identity.User{
      ...>   id: "01JB4E8T1H928QC6E1MP1XDZD8"
      ...> }, Bonfire.Data.Identity.Character)
      %Bonfire.Data.Identity.Character{
        id: "01JB4E8T1H928QC6E1MP1XDZD8"
      }

  """
  def maybe_to_struct(obj, type \\ nil)

  # Already the correct struct type
  def maybe_to_struct(%struct_type{} = obj, target_type)
      when target_type == struct_type,
      do: obj

  # Convert between struct types
  def maybe_to_struct(obj, type) when is_struct(obj) do
    struct_to_map(obj) |> maybe_to_struct(type)
  end

  # Handle string type names
  def maybe_to_struct(obj, type) when is_binary(type) do
    case Types.maybe_to_module(type) do
      module when is_atom(module) -> maybe_to_struct(obj, module)
      _ -> obj
    end
  end

  # Try inferring type from data if no explicit type provided
  def maybe_to_struct(obj, nil) do
    case schema_type(obj) do
      nil -> obj
      type -> maybe_to_struct(obj, type)
    end
  end

  # Convert to struct if module exists
  def maybe_to_struct(obj, type) when is_atom(type) do
    if Extend.module_exists?(type) do
      struct(type, obj)
    else
      obj
    end
  end

  # Fallback for no conversion
  def maybe_to_struct(obj, _type), do: obj

  @doc "Infer the struct or schema type from a map"
  def schema_type(%type{}), do: type
  def schema_type(%{__struct__: type}) when not is_nil(type), do: type
  def schema_type(%{__typename: type}) when not is_nil(type), do: type
  def schema_type(%{index_type: type}) when not is_nil(type), do: type
  def schema_type(_), do: nil

  # @doc """
  # Converts a map to a struct (based on MIT licensed function by Kum Sackey)
  # """
  # def struct_from_map(a_map, as: a_struct) do
  #   keys = Map.keys(Map.delete(a_struct, :__struct__))
  #   # Process map, checking for both string / atom keys
  #   for(
  #     key <- keys,
  #     into: %{},
  #     do: {key, Map.get(a_map, key) || Map.get(a_map, to_string(key))}
  #   )
  #   |> Map.merge(a_struct, ...)
  # end

  @doc """
  Counts the number of items in an enumerable that satisfy the given function.

  ## Examples

      iex> Bonfire.Common.Enums.count_where([1, 2, 3, 4, 5], fn x -> rem(x, 2) == 0 end)
      2

      iex> Bonfire.Common.Enums.count_where([:ok, :error, :ok], &(&1 == :ok))
      2
  """
  def count_where(collection, function \\ &is_nil/1) do
    Enum.reduce(collection, 0, fn item, count ->
      if function.(item), do: count + 1, else: count
    end)
  end

  @doc """
  Like `Enum.group_by/3`, except children are required to be unique (will throw otherwise!) and the resulting map does not wrap each item in a list.

  ## Examples

      iex> Bonfire.Common.Enums.group([1, 2, 3], fn x -> x end)
      %{1 => 1, 2 => 2, 3 => 3}

      > Bonfire.Common.Enums.group([:a, :b, :b, :c], fn x -> x end)
      ** (throw) "Expected a unique value"
  """
  def group([], fun) when is_function(fun, 1), do: %{}

  def group(list, fun)
      when is_list(list) and is_function(fun, 1),
      do: group(list, %{}, fun)

  defp group([x | xs], acc, fun),
    do: group(xs, group_item(fun.(x), x, acc), fun)

  defp group([], acc, _), do: acc

  defp group_item(key, _value, acc)
       when is_map_key(acc, key),
       do: throw("Expected a unique value")

  defp group_item(key, value, acc),
    do: Map.put(acc, key, value)

  @doc """
  Groups an enumerable by a function that returns key-value pairs, ensuring that keys are unique.

  ## Examples

      iex> Bonfire.Common.Enums.group_map([:a, :b, :c], fn x -> {x, to_string(x)} end)
      %{a: "a", b: "b", c: "c"}

      > Bonfire.Common.Enums.group_map([1, 2, 2, 3], fn x -> {x, x * 2} end)
      ** (throw) "Expected a unique value"
  """
  def group_map([], fun) when is_function(fun, 1), do: %{}

  def group_map(list, fun)
      when is_list(list) and is_function(fun, 1),
      do: group_map(list, %{}, fun)

  defp group_map([x | xs], acc, fun),
    do: group_map(xs, group_map_item(fun.(x), acc), fun)

  defp group_map([], acc, _), do: acc

  defp group_map_item({key, _value}, acc)
       when is_map_key(acc, key),
       do: throw("Expected a unique value")

  defp group_map_item({key, value}, acc),
    do: Map.put(acc, key, value)

  @doc """
  Filters the given value or enumerable and if it contains any `:error` tuple, return an `:error` tuple with a list of error values, other return an `:ok` tuple with a list of values.

  ## Examples

      iex> Bonfire.Common.Enums.all_oks_or_error([{:ok, 1}, {:error, "failed"}])
      {:error, ["failed"]}

      iex> Bonfire.Common.Enums.all_oks_or_error([{:ok, 2}, {:ok, 3}])
      {:ok, [2, 3]}

      iex> Bonfire.Common.Enums.all_oks_or_error({:error, "failed"})
      {:error, ["failed"]}

      iex> Bonfire.Common.Enums.all_oks_or_error({:ok, 1})
      {:ok, [1]}
  """
  def all_oks_or_error(enum) when is_list(enum) or is_map(enum) do
    case enum
         |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) do
      %{error: errors} -> {:error, errors}
      %{ok: results} -> {:ok, results}
    end
  end

  def all_oks_or_error({:ok, val}), do: {:ok, List.wrap(val)}
  def all_oks_or_error({:error, val}), do: {:error, List.wrap(val)}
  def all_oks_or_error(val), do: {:error, List.wrap(val)}

  @doc """
  Checks if there are any `:ok` tuples in the enumerable.

  ## Examples

      iex> Bonfire.Common.Enums.has_ok?([{:ok, 1}, {:error, "failed"}])
      true

      iex> Bonfire.Common.Enums.has_ok?([{:error, "failed"}])
      false
  """
  def has_ok?(enum) do
    has_tuple_key?(enum, :ok)
  end

  @doc """
  Checks if all tuples in the enumerable are `:ok`.

  ## Examples

      iex> Bonfire.Common.Enums.all_ok?([{:ok, 1}, {:ok, 2}])
      true

      iex> Bonfire.Common.Enums.all_ok?([{:ok, 1}, {:error, "failed"}])
      false
  """
  def all_ok?(enum) do
    !has_error?(enum)
  end

  @doc """
  Checks if there are any `:error` tuples in the enumerable.

  ## Examples

      iex> Bonfire.Common.Enums.has_error?([{:ok, 1}, {:error, "failed"}])
      true

      iex> Bonfire.Common.Enums.has_error?([{:ok, 1}])
      false
  """
  def has_error?(enum) do
    has_tuple_key?(enum, :error)
  end

  @doc """
  Checks if there are any tuples with the given key in the enumerable.

  ## Examples

      iex> Bonfire.Common.Enums.has_tuple_key?([{:ok, 1}, {:error, "failed"}], :ok)
      true

      iex> Bonfire.Common.Enums.has_tuple_key?([{:ok, 1}], :error)
      false
  """
  def has_tuple_key?(enum, key) do
    Enum.any?(enum, fn
      {i_key, _} -> i_key == key
      _ -> false
    end)
  end

  @doc """
  Unwraps tuples from a list of responses based on the specified key.

  ## Examples

      iex> Bonfire.Common.Enums.unwrap_tuples([{:ok, 1}, {:error, "failed"}, {:ok, 2}], :ok)
      [1, 2]

      iex> Bonfire.Common.Enums.unwrap_tuples([{:ok, 1}, {:error, "failed"}], :error)
      ["failed"]
  """
  def unwrap_tuples(enum, key) do
    # TODO: optimise & dedup all_oks_or_error?
    Enum.filter(enum, fn resp -> elem(resp, 0) == key end)
    |> Enum.map(fn v -> elem(v, 1) end)
    |> Enum.uniq()
    |> filter_empty(nil)
  end

  @doc """
  Ensures that the given keys in the map are not nil, replacing nil values with their provided defaults.

  ## Examples

      iex> Bonfire.Me.API.GraphQLMasto.Adapter.set_default_values(%{"avatar" => nil, "locked" => nil}, %{"avatar" => "", "locked" => false})
      %{"avatar" => "", "locked" => false}

      iex> Bonfire.Me.API.GraphQLMasto.Adapter.set_default_values(%{"avatar" => "a.png"}, %{"avatar" => ""})
      %{"avatar" => "a.png"}

  """
  def set_default_values(map, defaults) when is_map(map) and is_map(defaults) do
    Enum.reduce(defaults, map, fn {key, default}, acc ->
      Map.update(acc, key, default, fn
        nil -> default
        val -> val
      end)
    end)
  end

  # Check if all keys are atoms
  def atom_keys?(map) when is_map(map) do
    map |> Map.keys() |> Enum.all?(&is_atom/1)
  end

  # Check if all keys are strings
  def string_keys?(map) when is_map(map) do
    map |> Map.keys() |> Enum.all?(&is_binary/1)
  end
end
