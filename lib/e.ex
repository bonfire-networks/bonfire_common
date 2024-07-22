# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.E do
  @moduledoc "Helper to extract data nested in an object"

  import Untangle
  alias Bonfire.Common
  alias Bonfire.Common.Enums

  @doc "Returns a value, or a fallback if empty"
  def e(val, fallback \\ nil) do
    Enums.filter_empty(val, fallback)
  end

  @doc "Extracts a value from a map (and various other data structures), or returns a fallback if not present or empty. If more arguments are provided it looks for nested data (with the last argument always being the fallback)."
  def e({:ok, object}, key, fallback), do: e(object, key, fallback)

  # @decorate time()
  def e(%{__context__: context} = object, key, fallback) do
    # try searching in Surface's context (when object is assigns), if present
    case Enums.enum_get(object, key, nil) do
      result when is_nil(result) or result == fallback ->
        Enums.enum_get(context, key, nil)
        |> Common.maybe_fallback(fallback)

      result ->
        result
    end
  end

  def e(map, key, fallback) when is_map(map) do
    # attempt using key as atom or string, fallback if doesn't exist or is nil
    Enums.enum_get(map, key, nil)
    |> Common.maybe_fallback(fallback)
  end

  def e({key, v}, key, fallback) do
    Common.maybe_fallback(v, fallback)
  end

  def e([{key, v}], key, fallback) do
    Common.maybe_fallback(v, fallback)
  end

  def e({_, _}, _key, fallback) do
    fallback
  end

  def e([{_, _}], _key, fallback) do
    fallback
  end

  def e(list, key, fallback) when is_list(list) do
    # and length(list) == 1
    if Keyword.keyword?(list) do
      list |> Map.new() |> e(key, fallback)
    else
      debug(list, "trying to find #{key} in a list")

      Enum.find_value(list, &e(&1, key, nil))
      |> Common.maybe_fallback(fallback)
    end
  end

  # def e(list, key, fallback) when is_list(list) do
  #   if not Keyword.keyword?(list) do
  #     list |> Enum.reject(&is_nil/1) |> Enum.map(&e(&1, key, fallback))
  #   else
  #     list |> Map.new() |> e(key, fallback)
  #   end
  # end
  def e(object, key, fallback) do
    debug(object, "did not know how to find #{key} in")
    fallback
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
end
