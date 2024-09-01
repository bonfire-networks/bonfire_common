defmodule Bonfire.Common.Needles.Preload do
  @moduledoc "Helpers for preloading `Needle` Pointer associations. See also `Bonfire.Common.Repo.Preload`"

  # import Bonfire.Common.Config, only: [repo: 0]
  # alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  import Untangle

  @doc """
  Conditionally preloads pointers in an object based on provided keys and options.

  This function handles various cases including tuples with `{:ok, obj}`, maps with an `:edges` key, lists of objects, and individual objects. It supports both single and nested keys for preloading.

  ## Parameters
    - `object`: The object(s) in which pointers may be preloaded. This can be a map, list, tuple, or other data structures.
    - `keys`: A list of keys or a single key for preloading pointers. Nested keys can be specified for deeper levels of preloading.
    - `opts`: Options for preloading, which may include configuration for how pointers are fetched and handled.

  ## Examples

      iex> Bonfire.Common.Needles.Preload.maybe_preload_pointers(%{edges: [...]}, [:key], [])
      %{edges: [...]}

      iex> Bonfire.Common.Needles.Preload.maybe_preload_pointers(%{key: %Ecto.AssociationNotLoaded{}}, [:key], [])
      %{key: %LoadedObject{}}

      iex> Bonfire.Common.Needles.Preload.maybe_preload_pointers(%{key: %{nested_key: %Ecto.AssociationNotLoaded{}}}, [:key, :nested_key], [])
      %{key: %{nested_key: %LoadedObject{}}}
  """
  def maybe_preload_pointers(object, keys, opts \\ [])

  def maybe_preload_pointers({:ok, obj}, keys, opts),
    do: {:ok, maybe_preload_pointers(obj, keys, opts)}

  def maybe_preload_pointers(%{edges: list} = page, keys, opts) when is_list(list),
    do: Map.put(page, :edges, maybe_preload_pointers(list, keys, opts))

  def maybe_preload_pointers(list, keys, opts) when is_list(list) do
    debug("iterate list of objects")
    # TODO: optimise
    Enum.map(list, &maybe_preload_pointers(&1, keys, opts))
  end

  def maybe_preload_pointers(object, key, opts) when not is_struct(object) do
    error(object, "expected a struct or list of objects")
    object
  end

  def maybe_preload_pointers(object, keys, opts)
      when is_list(keys) and length(keys) == 1 do
    # TODO: handle any size list and merge with accelerator?
    key = List.first(keys)
    debug(key, "list with one key")
    maybe_preload_pointers(object, key, opts)
  end

  def maybe_preload_pointers(object, key, opts)
      when is_map(object) and is_atom(key) do
    debug(key, "one field")

    case Map.get(object, key) do
      %Needle.Pointer{} = pointer ->
        Map.put(object, key, maybe_preload_pointer(pointer, opts))

      _ ->
        object
    end
  end

  def maybe_preload_pointers(object, {key, nested_keys}, opts) do
    debug(nested_keys, "key #{inspect(key)} with nested keys")

    object
    |> maybe_preload_pointer(opts)
    # |> IO.inspect
    |> Map.put(
      key,
      Map.get(object, key)
      |> maybe_preload_pointers(nested_keys, opts)
    )
  end

  def maybe_preload_pointers(object, keys, _opts) do
    debug(keys, "ignore (only supports 1 key at a time)")
    object
  end

  @doc """
  Conditionally preloads nested pointers in object(s) based on provided keys and options.

  This function handles various cases including nested keys for preloading. It supports preloading pointers in objects, lists of objects, and nested structures. The function processes lists of keys for deeply nested preloading.

  ## Parameters
    - `object`: The object in which nested pointers may be preloaded. This can be a map, list, or other data structures.
    - `keys`: A list of nested keys for preloading pointers. The keys can be deeply nested to access and preload pointers at various levels (like in `proload` as opposed to `maybe_preload`)
    - `opts`: Options for preloading, which may include configuration for how pointers are fetched and handled.

  ## Examples

      iex> Bonfire.Common.Needles.Preload.maybe_preload_nested_pointers(%{key: %{nested_key: %Ecto.AssociationNotLoaded{}}}, [key: [:nested_key]], [])
      %{key: %{nested_key: %LoadedObject{}}}

      iex> Bonfire.Common.Needles.Preload.maybe_preload_nested_pointers(%{edges: []}, [:key], [])
      %{edges: []}

      iex> Bonfire.Common.Needles.Preload.maybe_preload_nested_pointers([%{key: %Ecto.AssociationNotLoaded{}}], [:key], [])
      [%{key: %LoadedObject{}}]
  """
  def maybe_preload_nested_pointers(object, keys, opts \\ [])

  def maybe_preload_nested_pointers({:ok, obj}, keys, opts),
    do: {:ok, maybe_preload_nested_pointers(obj, keys, opts)}

  def maybe_preload_nested_pointers(%{edges: list} = page, keys, opts) when is_list(list),
    do: Map.put(page, :edges, maybe_preload_nested_pointers(list, keys, opts))

  def maybe_preload_nested_pointers(object, keys, opts)
      when is_list(keys) and length(keys) > 0 and is_map(object) do
    debug(keys, "maybe_preload_nested_pointers: try object with list of keys")

    do_maybe_preload_nested_pointers(object, nested_keys(keys), opts)
  end

  def maybe_preload_nested_pointers(objects, keys, opts)
      when is_list(keys) and length(keys) > 0 and is_list(objects) and
             length(objects) > 0 do
    debug(keys, "maybe_preload_nested_pointers: try list with list of keys")

    do_maybe_preload_nested_pointers(
      Enum.reject(objects, &(&1 == [])),
      [Access.all()] ++ nested_keys(keys),
      opts
    )
  end

  def maybe_preload_nested_pointers(object, _, _opts), do: object

  defp do_maybe_preload_nested_pointers(object, keylist, opts)
       when is_struct(object) or
              (is_list(object) and not is_nil(keylist) and keylist != []) do
    debug(keylist, "do_maybe_preload_nested_pointers: try with get_and_update_in")

    # TODO: optimise by seeing how we can use Needles.follow! which supports a list of pointers to not preload these individually...
    # |> debug("object")
    with {_old, loaded} <-
           get_and_update_in(object, keylist, &preload_next_in/1) do
      loaded
      |> debug("object(s) with pointers loaded with get_and_update_in")
    end
  rescue
    e in KeyError ->
      error(e, "Could not preload nested pointers, returning the original object instead")
      object

    e in RuntimeError ->
      error(e, "Could not preload nested pointers, returning the original object instead")
      object
  end

  @doc """
  Preloads a single pointer if the provided value is a `Needle.Pointer`.

  ## Examples

      iex> Bonfire.Common.Needles.Preload.maybe_preload_pointer(%Needle.Pointer{...}, [])
      %LoadedObject{}

      iex> Bonfire.Common.Needles.Preload.maybe_preload_pointer("not_a_pointer", [])
      "not_a_pointer"
  """
  def maybe_preload_pointer(pointer, opts \\ [])

  def maybe_preload_pointer(%Needle.Pointer{} = pointer, opts) do
    debug("maybe_preload_pointer: follow")

    with {:ok, obj} <- Bonfire.Common.Needles.get(pointer, opts) do
      obj
    else
      e ->
        debug(pointer, "maybe_preload_pointer: could not fetch pointer: #{inspect(e)}")

        pointer
    end
  end

  # |> debug("skip")
  def maybe_preload_pointer(obj, _opts) do
    debug(obj, "not a Pointer Needle")
    obj
  end

  defp nested_keys(keys) do
    # keys |> Ecto.Repo.Preloader.normalize(nil, keys) |> IO.inspect
    # |> debug("flatten nested keys")
    keys
    |> Enums.flatter()
    |> Enum.map(&access_key(&1))

    # |> Enum.map(&custom_access_key_fun(&1))
  end

  @doc """
  Generates an access function based on a key and default value.

  ## Examples

      iex> Bonfire.Common.Needles.Preload.access_key(:key)
  """
  def access_key(key, default_val \\ nil) do
    fn
      # :get, data, next when is_list(data) ->
      #   debug(data, "get_original_valueS for #{key}")
      #   next.(Enum.map(data, fn subdata ->
      #     Map.get(subdata || %{}, key, default_val)
      #   end))

      :get, data, next ->
        # debug(data, "get_original_value for #{key}")
        next.(Map.get(data || %{}, key, default_val))

      # :get_and_update, data, next when is_list(data) ->
      #   debug(next, "funS for #{key}")

      #     value =
      #       Enum.map(data, fn subdata ->
      #         Map.get(subdata || %{}, key, default_val)
      #         |> debug("get_and_update_original_value for #{key}")
      #       end)

      #     case next.(value) |> debug("nexxt") do
      #       {get, update} -> {get, Map.put(data || %{}, key, update)}
      #       :pop -> {value, Map.delete(data || %{}, key)}
      #     end

      :get_and_update, data, next ->
        # debug(data, "data")
        # debug(next, "fun for #{key}")

        value =
          Map.get(data || %{}, key, default_val)

        # |> debug("get_and_update_original_value for #{key}")

        case next.(value) do
          {get, update} -> {get, Map.put(data || %{}, key, update)}
          :pop -> {value, Map.delete(data || %{}, key)}
        end
    end
  end

  @doc """
  Creates a custom access function for nested keys with an optional transformation function.

  ## Examples

      iex> Bonfire.Common.Needles.Preload.custom_access_key_fun(:key)
      #Function<...>
  """
  # TODO: to load multiple nested pointers
  def custom_access_key_fun(key, fun \\ &preload_next_in/1, default_val \\ nil) do
    fn
      :get, data, next ->
        # debug(data, "get_original_value for #{key}")
        next.(Map.get(data || %{}, key, default_val))

      :get_and_update, data, _next ->
        # debug(data, "data")
        # debug(fun, "fun for #{key}")

        value =
          Map.get(data || %{}, key, default_val)

        # |> debug("get_and_update_original_value for #{key}")

        case fun.(value) do
          {get, update} -> {get, Map.put(data || %{}, key, update)}
          :pop -> {value, Map.delete(data || %{}, key)}
        end
    end
  end

  defp preload_next_in(%Needle.Pointer{} = value) do
    # debug(value, "preload_next_in_value")
    {value, maybe_preload_pointer(value, skip_boundary_check: true)}
  end

  defp preload_next_in(value) do
    debug(value, "not a Pointer Needle")
    {value, value}
  end
end
