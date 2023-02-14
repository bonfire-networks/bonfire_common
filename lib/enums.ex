# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.Enums do
  @moduledoc "Missing functions from Enum"
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

  def id(id) when is_binary(id), do: id
  def id(%{id: id}) when is_binary(id), do: id
  def id(%Changeset{} = cs), do: id(Changeset.get_field(cs, :id))
  def id({:id, id}) when is_binary(id), do: id
  def id(%{"id" => id}) when is_binary(id), do: id

  def id(ids) when is_list(ids),
    do: ids |> maybe_flatten() |> Enum.map(&id/1) |> filter_empty(nil)

  def id({:ok, other}), do: id(other)

  def id(id) do
    e = "Expected an ID (or an object with one), got #{inspect(id)}"
    # throw {:error, e}
    debug(e)
    nil
  end

  def map_new(data, fallback_key \\ :data) do
    if Enumerable.impl_for(data),
      do: Map.new(data),
      else: Map.put(%{}, fallback_key, data)
  end

  @doc """
  Attempt geting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def enum_get(map, key, fallback) when is_map(map) and is_atom(key) do
    case maybe_get(map, key, :empty) do
      :empty -> maybe_get(map, Atom.to_string(key), fallback)
      val -> val
    end
  end

  # doc """ Attempt geting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback """
  def enum_get(map, key, fallback) when is_map(map) and is_binary(key) do
    case maybe_get(map, key, :empty) do
      :empty ->
        case maybe_get(map, Recase.to_camel(key), :empty) do
          :empty ->
            maybe_get(map, Types.maybe_to_atom(key), fallback)

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

  def uniq_by_id(list) do
    Enum.uniq_by(list, &Utils.e(&1, :id, &1))
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

  defp magic_filter_empty(val, map, key, fallback \\ nil)

  defp magic_filter_empty(
         %Ecto.Association.NotLoaded{},
         %{__struct__: schema} = map,
         key,
         fallback
       )
       when is_map(map) and is_atom(key) do
    if Config.get!(:env) == :dev && Config.get(:e_auto_preload, false) do
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

  def filter_empty(val, fallback)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback
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
      |> filter_empty_enum()
      |> Enum.into(%{})
      |> re_filter_empty(fallback)

  def filter_empty(val, _fallback), do: val

  defp filter_empty_enum(enum),
    do:
      enum
      |> Enum.map(fn
        {key, val} -> {key, filter_empty(val, nil)}
        val -> filter_empty(val, nil)
      end)
      |> Enum.filter(fn
        {_key, nil} -> false
        nil -> false
        _ -> true
      end)

  defp re_filter_empty([], fallback), do: fallback
  defp re_filter_empty(map, fallback) when is_map(map) and map == %{}, do: fallback
  defp re_filter_empty(nil, fallback), do: fallback
  defp re_filter_empty(val, _fallback), do: val

  def maybe_list(val, change_fn) when is_list(val) do
    change_fn.(val)
  end

  def maybe_list(val, _) do
    val
  end

  def elem_or(verb, index, _fallback) when is_tuple(verb), do: elem(verb, index)
  def elem_or(_verb, _index, fallback), do: fallback

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
      |> Types.ulid()
    end
  end

  @doc "conditionally update a map"
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "recursively merge structs, maps or lists (into a struct or map)"
  def deep_merge(left, right, opts \\ [])

  def deep_merge(%Ecto.Changeset{} = left, %Ecto.Changeset{} = right, opts) do
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
        left ++ right
      end
    end
  end

  def deep_merge(left, right, _opts) do
    right
  end

  # Key exists in both maps - these can be merged recursively.
  defp deep_resolve(_key, left, right, opts \\ [])

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

  def deep_merge_reduce(list_or_map, opts \\ [])
  def deep_merge_reduce([], _opts), do: []
  # to avoid Enum.EmptyError
  def deep_merge_reduce([only_one], _opts), do: only_one

  def deep_merge_reduce(list_or_map, opts) do
    Enum.reduce(list_or_map, fn elem, acc ->
      deep_merge(acc, elem, opts)
    end)
  end

  @doc "merge maps or lists (into a map)"
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

  def merge_changesets(%Ecto.Changeset{prepare: p1} = cs1, %Ecto.Changeset{prepare: p2} = cs2)
      when is_list(p1) and is_list(p2) and p2 != [] do
    info("workaround for `Ecto.Changeset.merge` not merging prepare")
    %{Ecto.Changeset.merge(cs1, cs2) | prepare: p1 ++ p2}
  end

  def merge_changesets(%Ecto.Changeset{} = cs1, %Ecto.Changeset{} = cs2) do
    info(cs1.prepare, "merge without prepare")
    info(cs2.prepare, "merge without prepare")
    Ecto.Changeset.merge(cs1, cs2)
  end

  def merge_keeping_only_first_keys(map_1, map_2) do
    map_1
    |> Map.keys()
    |> then(&Map.take(map_2, &1))
    |> then(&Map.merge(map_1, &1))
  end

  @doc "Append an item to a list if it is not nil"
  @spec maybe_append([any()], any()) :: [any()]
  def maybe_append(list, value) when is_nil(value) or value == [], do: list

  def maybe_append(list, {:ok, value}) when is_nil(value) or value == [],
    do: list

  def maybe_append(list, value) when is_list(list), do: [value | list]
  def maybe_append(obj, value), do: maybe_append([obj], value)

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
    # |> debug("clean")
    |> map_filter_empty()
  end

  def struct_to_map(other), do: other

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
  Converts an enumerable to a list recursively
  Note: make sure that all keys are atoms, i.e. using `input_to_atoms` first
  """
  def maybe_to_keyword_list(obj, recursive \\ false)

  def maybe_to_keyword_list(obj, true = recursive)
      when is_map(obj) or is_list(obj) do
    obj
    |> maybe_to_keyword_list(false)
    |> do_maybe_to_keyword_list()
  end

  def maybe_to_keyword_list(obj, false = _recursive)
      when is_map(obj) or is_list(obj) do
    Enum.filter(obj, fn
      {k, _v} -> is_atom(k)
      v -> v
    end)
  end

  def maybe_to_keyword_list(obj, _), do: obj

  defp do_maybe_to_keyword_list(object) do
    if Keyword.keyword?(object) or is_map(object) do
      Keyword.new(object, fn
        {k, v} -> {k, maybe_to_keyword_list(v, true)}
        v -> maybe_to_keyword_list(v, true)
      end)
    else
      object
    end
  end

  def nested_structs_to_maps(struct = %type{}) when type != DateTime,
    do: nested_structs_to_maps(struct_to_map(struct))

  def nested_structs_to_maps(v) when not is_map(v), do: v

  def nested_structs_to_maps(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {k, nested_structs_to_maps(v)} end)
    |> Enum.into(%{})
  end

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
  Convert map atom keys to strings
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

  def input_to_atoms(
        data,
        discard_unknown_keys \\ true,
        including_values \\ false
      )

  # skip structs
  def input_to_atoms(data, _, _) when is_struct(data) do
    data
  end

  def input_to_atoms(%{} = data, true = discard_unknown_keys, including_values) do
    # turn any keys into atoms (if such atoms already exist) and discard the rest
    :maps.filter(
      fn k, _v -> is_atom(k) end,
      data
      |> Map.drop(["_csrf_token"])
      |> Map.new(fn {k, v} ->
        {
          Types.maybe_to_snake_atom(k) || Types.maybe_to_module(k, false),
          input_to_atoms(v, discard_unknown_keys, including_values)
        }
      end)
    )
  end

  def input_to_atoms(%{} = data, false = discard_unknown_keys, including_values) do
    data
    |> Map.drop(["_csrf_token"])
    |> Map.new(fn {k, v} ->
      {
        Types.maybe_to_snake_atom(k) || Types.maybe_to_module(k, false) || k,
        input_to_atoms(v, discard_unknown_keys, including_values)
      }
    end)
  end

  def input_to_atoms(list, true = _discard_unknown_keys, including_values)
      when is_list(list) do
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

  # support truthy/falsy values
  def input_to_atoms("nil", _, true = _including_values), do: nil
  def input_to_atoms("false", _, true = _including_values), do: false
  def input_to_atoms("true", _, true = _including_values), do: true

  def input_to_atoms(v, _, true = _including_values) when is_binary(v) do
    Types.maybe_to_module(v, false) || v
  end

  def input_to_atoms(v, _, _), do: v

  def maybe_to_structs(v) when is_struct(v), do: v

  def maybe_to_structs(v),
    do: v |> input_to_atoms() |> maybe_to_structs_recurse()

  defp maybe_to_structs_recurse(data, parent_id \\ nil)

  defp maybe_to_structs_recurse(%{index_type: type} = data, parent_id) do
    data
    |> Map.new(fn {k, v} ->
      {k, maybe_to_structs_recurse(v, Utils.e(data, :id, nil))}
    end)
    |> maybe_add_mixin_id(parent_id)
    |> maybe_to_struct(type)
  end

  defp maybe_to_structs_recurse(%{} = data, parent_id) do
    Map.new(data, fn {k, v} ->
      {k, maybe_to_structs_recurse(v, Utils.e(data, :id, nil))}
    end)
  end

  defp maybe_to_structs_recurse(v, _), do: v

  defp maybe_add_mixin_id(%{id: id} = data, _parent_id) when not is_nil(id),
    do: data

  defp maybe_add_mixin_id(data, parent_id) when not is_nil(parent_id),
    do: Map.merge(data, %{id: parent_id})

  defp maybe_add_mixin_id(data, parent_id), do: data

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

  def maybe_to_struct(obj, module) when is_atom(module) do
    debug("to_struct with module #{module}")
    # if module_enabled?(module) and module_enabled?(Mappable) do
    #   Mappable.to_struct(obj, module)
    # else
    if module_enabled?(module),
      do: struct(module, obj),
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

  def count_where(collection, function) do
    Enum.reduce(collection, 0, fn item, count ->
      if function.(item), do: count + 1, else: count
    end)
  end

  @doc """
  Like group_by, except children are required to be unique (will throw
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

  def enum_maybe_apply(map, fun, args) when is_map(map) do
    Utils.maybe_apply(Map, fun, [map] ++ List.wrap(args))
  end

  def enum_maybe_apply(list, fun, args) when is_list(list) do
    if Keyword.keyword?(list) do
      Utils.maybe_apply(Keyword, fun, [list] ++ List.wrap(args))
    else
      Utils.maybe_apply(List, fun, [list] ++ List.wrap(args))
    end
  end
end
