# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.E do
  @moduledoc "Helper to extract data nested in an object"

  require Pathex
  import Untangle
  use Arrows

  alias Bonfire.Common
  alias Bonfire.Common.Config
  alias Bonfire.Common.Enums

  defmacro __using__(_opts \\ []) do
    quote do
      require Pathex
      alias Bonfire.Common
      import Common.E
    end
  end

  @doc """
  Extracts a value from a map or other data structure, or returns a fallback if not present or empty.
  If additional arguments are provided, it searches for nested data structures, with the last argument always being the fallback.

  ## Examples

      iex> e(%{key: "value"}, :key, "fallback")
      "value"

      iex> e(%{key: nil}, :key, "fallback")
      "fallback"

      iex> e(%{key: "value"}, :missing_key, "fallback")
      "fallback"

      iex> e(%{key: %Ecto.Association.NotLoaded{}}, :key, "fallback")
      "fallback"

      iex> e(%{key: %Ecto.Association.NotLoaded{}}, :key, :nil!)
      ** (RuntimeError) Required value not found for keys :key in object

      iex> e({:ok, %{key: "value"}}, :key, "fallback") 
      "value"

      iex> e(%{__context__: %{key: "context_value"}}, :key, "fallback") 
      "context_value"

      iex> e(%{a: %{b: "value"}}, :a, :b, "fallback")
      "value"

      iex> e(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, "fallback")
      "fallback"

      iex> e(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, :nil!)
      ** (RuntimeError) Required value not found for keys [:a, :b] in object

      iex> e(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, :c, :nil!)
      ** (RuntimeError) Required value not found for keys [:a, :b, :c] in object

      iex> e(%{a: %{b: nil}}, :a, :b, "fallback")
      "fallback"

      iex> e(%{a: %{b: %{c: "value"}}}, :a, :b, :c, "fallback")
      "value"

      iex> e(%{a: %{b: %{c: "value"}}}, :a, :b, :c, :d, "fallback")
      "fallback"

      iex> e(%{a: %{b: %{c: %{d: "value"}}}}, :a, :b, :c, :d, "fallback")
      "value"

      iex> e(%{a: %{b: %{c: %{d: "value"}}}}, :a, :b, :c, :d, :ed, "fallback")
      "fallback"

      iex> e(%{a: %{b: %{c: %{d: %{e: "value"}}}}}, :a, :b, :c, :d, :e, "fallback")
      "value"

  """
  #  in case Pathex was disabled in config, we use the runtime `ed` functions instead
  if Config.__get__(:use_pathex, true) do
    defmacro e(object, key1, fallback) do
      quote do
        key1 = unquote(key1)
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(key1),
               nil
             ) do
          nil -> Common.E.e_fallback_ed(object, [key1], unquote(fallback))
          ret -> handle_fallback(object, unquote(key1), ret, unquote(fallback))
        end
      end
    end

    defmacro e(object, key1, key2, fallback) do
      quote do
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(unquote(key1) / unquote(key2)),
               nil
             ) do
          nil ->
            Common.E.e_fallback_ed(object, [unquote(key1), unquote(key2)], unquote(fallback))

          ret ->
            handle_fallback(
              object,
              [
                unquote(key1),
                unquote(key2)
              ],
              ret,
              unquote(fallback)
            )
        end
      end
    end

    defmacro e(object, key1, key2, key3, fallback) do
      quote do
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(unquote(key1) / unquote(key2) / unquote(key3)),
               nil
             ) do
          nil ->
            Common.E.e_fallback_ed(
              object,
              [unquote(key1), unquote(key2), unquote(key3)],
              unquote(fallback)
            )

          ret ->
            handle_fallback(
              object,
              [
                unquote(key1),
                unquote(key2),
                unquote(key3)
              ],
              ret,
              unquote(fallback)
            )
        end
      end
    end

    defmacro e(object, key1, key2, key3, key4, fallback) do
      quote do
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(unquote(key1) / unquote(key2) / unquote(key3) / unquote(key4)),
               nil
             ) do
          nil ->
            Common.E.e_fallback_ed(
              object,
              [unquote(key1), unquote(key2), unquote(key3), unquote(key4)],
              unquote(fallback)
            )

          ret ->
            handle_fallback(
              object,
              [
                unquote(key1),
                unquote(key2),
                unquote(key3),
                unquote(key4)
              ],
              ret,
              unquote(fallback)
            )
        end
      end
    end

    defmacro e(object, key1, key2, key3, key4, key5, fallback) do
      quote do
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(
                 unquote(key1) / unquote(key2) / unquote(key3) / unquote(key4) / unquote(key5)
               ),
               nil
             ) do
          nil ->
            Common.E.e_fallback_ed(
              object,
              [unquote(key1), unquote(key2), unquote(key3), unquote(key4), unquote(key5)],
              unquote(fallback)
            )

          ret ->
            handle_fallback(
              object,
              [
                unquote(key1),
                unquote(key2),
                unquote(key3),
                unquote(key4),
                unquote(key5)
              ],
              ret,
              unquote(fallback)
            )
        end
      end
    end

    defmacro e(object, key1, key2, key3, key4, key5, key6, fallback) do
      quote do
        object = unquote(object)

        case Pathex.get(
               object,
               Pathex.path(
                 unquote(key1) / unquote(key2) / unquote(key3) / unquote(key4) / unquote(key5) /
                   unquote(key6)
               ),
               nil
             ) do
          nil ->
            Common.E.e_fallback_ed(
              object,
              [
                unquote(key1),
                unquote(key2),
                unquote(key3),
                unquote(key4),
                unquote(key5),
                unquote(key6)
              ],
              unquote(fallback)
            )

          ret ->
            handle_fallback(
              object,
              [
                unquote(key1),
                unquote(key2),
                unquote(key3),
                unquote(key4),
                unquote(key5),
                unquote(key6)
              ],
              ret,
              unquote(fallback)
            )
        end
      end
    end
  else
    defdelegate e(object, key1, fallback), to: __MODULE__, as: :ed
    defdelegate e(object, key1, key2, fallback), to: __MODULE__, as: :ed
    defdelegate e(object, key1, key2, key3, fallback), to: __MODULE__, as: :ed
    defdelegate e(object, key1, key2, key3, key4, fallback), to: __MODULE__, as: :ed
    defdelegate e(object, key1, key2, key3, key4, key5, fallback), to: __MODULE__, as: :ed
    defdelegate e(object, key1, key2, key3, key4, key5, key6, fallback), to: __MODULE__, as: :ed
  end

  @doc """
  Returns a value if it is not empty, or a fallback value if it is empty.

  This function delegates to `Bonfire.Common.Enums.filter_empty/2` to determine if `val` is empty and returns `fallback` if so.

  ## Examples

      iex> ed("non-empty value", "fallback")
      "non-empty value"

      iex> ed("", "fallback")
      "fallback"

      iex> ed(nil, "fallback")
      "fallback"

  """
  def ed(val, fallback \\ nil) do
    Enums.filter_empty(val, nil)
    |> Common.maybe_fallback(fallback)
  end

  def e(val, fallback \\ nil) do
    Enums.filter_empty(val, nil)
    |> Common.maybe_fallback(fallback)
  end

  @doc """
  Extracts a value from a map or other data structure, or returns a fallback if not present or empty.
  If additional arguments are provided, it searches for nested data structures, with the last argument always being the fallback.

  ## Examples

      iex> ed(%{key: "value"}, :key, "fallback")
      "value"

      iex> ed(%{key: nil}, :key, "fallback")
      "fallback"

      iex> ed(%{key: "value"}, :missing_key, "fallback")
      "fallback"

      iex> ed(%{key: %Ecto.Association.NotLoaded{}}, :key, "fallback")
      "fallback"

      iex> ed(%{key: %Ecto.Association.NotLoaded{}}, :key, :nil!)
      ** (RuntimeError) Required value not found for keys :key in object

      iex> ed({:ok, %{key: "value"}}, :key, "fallback")
      "value"

      iex> ed(%{__context__: %{key: "context_value"}}, :key, "fallback")
      "context_value"

      iex> ed(%{a: %{b: "value"}}, :a, :b, "fallback")
      "value"

      iex> ed(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, "fallback")
      "fallback"

      iex> ed(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, :nil!)
      ** (RuntimeError) Required value not found for keys [:a, :b] in object

      iex> ed(%{a: %{b: %Ecto.Association.NotLoaded{}}}, :a, :b, :c,  :nil!)
      ** (RuntimeError) Required value not found for keys [:a, :b, :c] in object

      iex> ed(%{a: %{b: "value"}}, [:a, :b], "fallback")
      "value"

      iex> ed(%{a: %{b: nil}}, :a, :b, "fallback")
      "fallback"

      iex> ed(%{a: %{b: %{c: "value"}}}, :a, :b, :c, "fallback")
      "value"

      iex> ed(%{a: %{b: %{c: "value"}}}, :a, :b, :c, :d, "fallback")
      "fallback"

      iex> ed(%{a: %{b: %{c: %{d: "value"}}}}, :a, :b, :c, :d, "fallback")
      "value"

      iex> ed(%{a: %{b: %{c: %{d: "value"}}}}, :a, :b, :c, :d, :ed, "fallback")
      "fallback"

      iex> ed(%{a: %{b: %{c: %{d: %{e: "value"}}}}}, :a, :b, :c, :d, :e, "fallback")
      "value"

  """
  def ed({:ok, object}, key, fallback), do: ed(object, key, fallback)

  def ed(map, keys, fallback) when is_map(map) and is_list(keys) do
    get_in_access_keys_or(map, keys, fallback, fn map ->
      # TODO: optimise, right now if get_in didn't work, we call ed again but with one-param-per-key
      apply(__MODULE__, :ed, [map] ++ keys ++ [fallback])
    end)
  end

  # @decorate time()
  def ed(%{__context__: context} = object, key, fallback) do
    # try searching in Surface's context (when object is assigns), if present
    case Enums.get_eager(object, key, nil) do
      result when is_nil(result) or result == fallback ->
        Enums.get_eager(context, key, nil)
        |> handle_fallback(object, key, ..., fallback)

      result ->
        result
    end
  end

  def ed(map, key, fallback) when is_map(map) do
    get_in_access_keys_or(map, key, fallback, fn map ->
      # if get_in didn't work, try using key as atom or string, and return fallback if doesn't exist or is nil
      Enums.get_eager(map, key, nil)
      |> handle_fallback(map, key, ..., fallback)
    end)
  end

  def ed({key, v}, key, fallback) do
    handle_fallback(v, key, v, fallback)
  end

  def ed([{key, v}], key, fallback) do
    handle_fallback(v, key, v, fallback)
  end

  def ed({_, _} = object, key, fallback) do
    handle_fallback(object, key, nil, fallback)
  end

  def ed([{_, _}] = object, key, fallback) do
    handle_fallback(object, key, nil, fallback)
  end

  def ed(list, key, fallback) when is_list(list) do
    # and length(list) == 1
    if Keyword.keyword?(list) do
      list |> Map.new() |> ed(key, fallback)
    else
      debug(list, "trying to find #{inspect(key)} in a list")

      Enum.find_value(list, &ed(&1, key, nil))
      |> handle_fallback(list, key, ..., fallback)
    end
  end

  # def ed(list, key, fallback) when is_list(list) do
  #   if not Keyword.keyword?(list) do
  #     list |> Enum.reject(&is_nil/1) |> Enum.map(&ed(&1, key, fallback))
  #   else
  #     list |> Map.new() |> ed(key, fallback)
  #   end
  # end
  def ed(object, key, fallback) do
    warn(object, "did not know how to find #{key} in")
    handle_fallback(object, key, nil, fallback)
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def ed(object, key1, key2, fallback) do
    get_in_access_keys_or(object, [key1, key2], fallback, fn object ->
      # if get_in didn't work, revert to peeling one layer at a time
      ed(object, key1, %{})
      |> ed(key2, %Ecto.Association.NotLoaded{})
    end)
  end

  def ed(object, key1, key2, key3, fallback) do
    get_in_access_keys_or(object, [key1, key2, key3], fallback, fn object ->
      ed(object, key1, key2, %{})
      |> ed(key3, %Ecto.Association.NotLoaded{})
    end)
  end

  def ed(object, key1, key2, key3, key4, fallback) do
    get_in_access_keys_or(object, [key1, key2, key3, key4], fallback, fn object ->
      ed(object, key1, key2, key3, %{})
      |> ed(key4, %Ecto.Association.NotLoaded{})
    end)
  end

  def ed(object, key1, key2, key3, key4, key5, fallback) do
    get_in_access_keys_or(object, [key1, key2, key3, key4, key5], fallback, fn object ->
      ed(object, key1, key2, key3, key4, %{})
      |> ed(key5, %Ecto.Association.NotLoaded{})
    end)
  end

  def ed(object, key1, key2, key3, key4, key5, key6, fallback) do
    get_in_access_keys_or(object, [key1, key2, key3, key4, key5, key6], fallback, fn object ->
      ed(object, key1, key2, key3, key4, key5, %{})
      |> ed(key6, %Ecto.Association.NotLoaded{})
    end)
  end

  def e_fallback_ed({:ok, object}, keys, fallback) do
    # TODO: can we pattern match that before the first call to Pathex instead? 
    # apply(__MODULE__, :e, [object] ++ keys ++ [fallback])
    # e(object, unquote_splicing(keys), fallback)
    # quote do
    #   e(object, unquote_splicing(keys), fallback)
    # end
    apply(__MODULE__, :ed, [object] ++ keys ++ [fallback])
  end

  def e_fallback_ed(%{__context__: object}, keys, fallback) do
    apply(__MODULE__, :ed, [object] ++ keys ++ [fallback])
  end

  def e_fallback_ed(object, keys, :nil!) do
    handle_fallback(object, keys, %Ecto.Association.NotLoaded{}, :nil!)
  end

  def e_fallback_ed(object, keys, fallback) do
    handle_fallback(object, keys, nil, fallback)
  end

  defp get_in_access_keys_or(map, keys, fallback, fallback_fun) when is_map(map) do
    case Enums.get_in_access_keys(map, keys, :empty) do
      :empty ->
        fallback_fun.(map)

      val ->
        val
    end
    |> handle_fallback(map, keys, ..., fallback)
  end

  defp get_in_access_keys_or(map, keys, fallback, fallback_fun) do
    fallback_fun.(map)
    |> handle_fallback(map, keys, ..., fallback)
  end

  def handle_fallback(_object, _keys, nil, nil), do: nil

  def handle_fallback(object, keys, "", fallback),
    do: handle_fallback(object, keys, nil, fallback)

  def handle_fallback(object, keys, %Ecto.Association.NotLoaded{}, :nil!) do
    Untangle.err(object, "Required value not found for keys #{inspect(keys)} in object")
    nil
  end

  def handle_fallback(object, keys, %Ecto.Association.NotLoaded{}, fallback),
    do: handle_fallback(object, keys, nil, fallback)

  def handle_fallback(_object, _keys, nil, fun) when is_function(fun, 0), do: fun.()
  def handle_fallback(object, keys, nil, fun) when is_function(fun, 2), do: fun.(object, keys)
  def handle_fallback(_object, _keys, nil, fallback), do: fallback
  def handle_fallback(_object, _keys, val, _), do: val
end
