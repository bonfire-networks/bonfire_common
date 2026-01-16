defmodule Bonfire.Common.Cache do
  @moduledoc """
  Helpers for caching data and operations.

  This module provides functions to efficiently cache values and function results,
  with automatic expiration. Use it to avoid repeating expensive operations.
  """

  use Untangle
  use Arrows
  alias Bonfire.Common.Utils
  use Bonfire.Common.Config

  # 6 hours
  @default_cache_ttl 1_000 * 60 * 60 * 6
  # 5 min
  @error_cache_ttl 1_000 * 60 * 5

  @default_store :bonfire_cache

  # TODO: explore using Decorator lib to support decorating functions to cache them
  # use Decorator.Define, cache: 0
  # def cache(fn_body, context) do
  # end

  @doc """
  Stores a value in the cache with the given key and options.

  ## Options
    * `:cache_store` - The cache store to use (defaults to #{inspect(@default_store)})
    * `:expire` - Time in milliseconds until the cache entry expires (defaults to #{@default_cache_ttl}ms meaning 6 hours)

  ## Examples

      iex> Bonfire.Common.Cache.put("my_key", "my_value")
      "my_value"
      iex> Bonfire.Common.Cache.get("my_key")
      {:ok, "my_value"}

      iex> Bonfire.Common.Cache.put("expires_soon", "temporary", expire: 1000)
      "temporary"
  """
  def put(key, value, opts \\ []) do
    Cachex.put(
      opts[:cache_store] || default_cache_store(),
      key,
      value,
      opts |> Keyword.put_new(:expire, @default_cache_ttl)
    )

    value
  end

  @doc """
  Retrieves a value from the cache with the given key.

  Returns `{:ok, value}` if the key exists, `{:ok, nil}` if the key does not exist, or `{:error, reason}` if there was an error.

  ## Options
    * `:cache_store` - The cache store to use (defaults to #{inspect(@default_store)})

  ## Examples

      iex> Bonfire.Common.Cache.put("fetch_me", "hello")
      iex> Bonfire.Common.Cache.get("fetch_me")
      {:ok, "hello"}
      
      iex> Bonfire.Common.Cache.get("non_existent_key")
      {:ok, nil}
  """
  def get(key, opts \\ []), do: Cachex.get(opts[:cache_store] || default_cache_store(), key)

  @doc """
  Retrieves a value from the cache with the given key and unwraps the result.

  Returns the value if the key exists or nil if it doesn't exist or there was an error.

  ## Options
    * `:cache_store` - The cache store to use (defaults to #{inspect(@default_store)})

  ## Examples

      iex> Bonfire.Common.Cache.put("my_key", "my_value")
      iex> Bonfire.Common.Cache.get!("my_key")
      "my_value"
      
      iex> Bonfire.Common.Cache.get!("missing_key")
      nil
  """
  def get!(key, opts \\ []) do
    case get(key, opts) do
      {:ok, val} ->
        val

      {:error, e} ->
        error(e)
        nil

      _ ->
        nil
    end
  end

  @doc """
  Removes the entry associated with a key from the cache.

  ## Options
    * `:cache_store` - The cache store to use (defaults to `default_cache_store/0`})

  ## Examples

      iex> Bonfire.Common.Cache.put("delete_me", "value")
      iex> Bonfire.Common.Cache.remove("delete_me")
      iex> Bonfire.Common.Cache.get!("delete_me")
      nil
  """
  def remove(key, opts \\ []) do
    Cachex.del(opts[:cache_store] || default_cache_store(), key)
    # ~> debug("Removed from cache: #{inspect key}")
  end

  @doc """
  Clears all entries from the cache.

  ## Options
    * `:cache_store` - The cache store to use (defaults to #{inspect(@default_store)})

  ## Examples

      iex> Bonfire.Common.Cache.remove_all()
      iex> Bonfire.Common.Cache.put("key1", "value1")
      iex> Bonfire.Common.Cache.put("key2", "value2")
      iex> _removed_count = Bonfire.Common.Cache.remove_all()
      iex> Bonfire.Common.Cache.get!("key1")
      nil
  """
  def remove_all(opts \\ []) do
    store = opts[:cache_store] || default_cache_store()

    Cachex.clear(store)
    ~> debug("Cleared cache: #{store}")
  end

  @doc """
  Takes a function (or module and function names) and a set of arguments for that function,  and tries to fetch the previous result of running that function from the in-memory cache, and if it's not in the cache it executes the function, and caches and returns the result.

  Uses the MFA (module name/function name/arguments used) to generate the cache key (see `key_for_call/2` and `args_to_string/1`).

  ## Options
    * `:cache_store` - The cache store to use (defaults to #{inspect(@default_store)})
    * `:cache_key` - Custom cache key to use (defaults to auto-generated key based on function and args)
    * `:expire` - Time in milliseconds until the cache entry expires (defaults to #{@default_cache_ttl}ms)
    * `:check_env` - When set to false, bypasses error-retry logic in dev environment (defaults to true)

  ## Examples

      iex> Bonfire.Common.Cache.maybe_apply_cached({String, :upcase}, ["hello"])
      "HELLO"
      
      iex> # Second call uses cached result
      iex> Bonfire.Common.Cache.maybe_apply_cached({String, :upcase}, ["hello"])
      "HELLO"

      iex> Bonfire.Common.Cache.maybe_apply_cached(fn x -> x * 2 end, [21])
      42
  """
  def maybe_apply_cached(fun, args \\ [], opts \\ [])

  def maybe_apply_cached(fun, args, opts) when is_function(fun) and is_list(args) do
    opts
    # |> debug()
    |> Keyword.put_new_lazy(:cache_key, fn ->
      key_for_call(fun, args)
    end)
    |> do_maybe_apply_cached(fun, args, ...)
  end

  def maybe_apply_cached({module, fun}, args, opts)
      when is_atom(module) and is_atom(fun) and is_list(args) do
    opts
    |> Keyword.put_new_lazy(:cache_key, fn ->
      key_for_call({module, fun}, args)
    end)
    |> do_maybe_apply_cached(module, fun, args, ...)
  end

  def maybe_apply_cached(fun, args, opts), do: maybe_apply_cached(fun, [args], opts)

  @doc """
  Removes the result of a given function ran using `maybe_apply_cached/3` from the cache.

  This is useful when you know a cached value is stale and want to force
  re-computation on the next call.

  ## Options
    * `:cache_store` - The cache store to use (defaults to `default_cache_store/0`})

  ## Examples

      iex> Bonfire.Common.Cache.maybe_apply_cached({String, :upcase}, ["hello"])
      "HELLO"
      iex> Bonfire.Common.Cache.reset({String, :upcase}, ["hello"])
      iex> # Will compute the result again
      iex> Bonfire.Common.Cache.maybe_apply_cached({String, :upcase}, ["hello"])
      "HELLO"
  """
  def reset(fun, args, opts \\ []) do
    key_for_call(fun, args)
    |> remove(opts)
  end

  @doc """
  Generates a cache key for a function and its arguments.

  This function is used internally by `maybe_apply_cached/3` to create consistent cache keys based on function references and their arguments.

  ## Examples

      iex> Bonfire.Common.Cache.key_for_call(fn x -> x * 2 end, [21])
      iex> # Returns something like "fn/1 in Bonfire.Common.Cache.key_for_call/2(21)"
      iex> # FYI actual result in doctest is more like "Bonfire.Common.CashTest."doctest Bonfire.Common.Cache.key_for_call/2 (13)"/1(21)"
      
      iex> Bonfire.Common.Cache.key_for_call({String, :upcase}, "hello")
      "String.upcase(\\\"hello\\\")"

      iex> Bonfire.Common.Cache.key_for_call({String, :upcase}, ["hello"])
      "String.upcase(\\\"hello\\\")"
      
      iex> Bonfire.Common.Cache.key_for_call({Map, :get}, [%{"a"=>1, b: 2}, :a])
      "Map.get([{:b, 2}, {\\\"a\\\", 1}], :a)"
  """
  def key_for_call(fun, args) when is_function(fun) do
    mod_fun =
      String.split(inspect(fun), " in ")
      |> List.last()
      |> String.trim_leading("anonymous ")
      |> String.trim_trailing(">")

    "#{mod_fun}(#{args_to_string(args)})"
  end

  def key_for_call({module, fun}, args)
      when is_atom(module) and is_atom(fun) do
    "#{String.trim_leading(Atom.to_string(module), "Elixir.")}.#{fun}(#{args_to_string(args)})"
  end

  defp do_maybe_apply_cached(module \\ nil, fun, args, opts) do
    # debug(opts)
    key = Keyword.fetch!(opts, :cache_key)
    expire = opts[:expire] || @default_cache_ttl
    cache_store = opts[:cache_store] || default_cache_store()

    if Code.loaded?(Cachex) and :ets.whereis(cache_store) != :undefined do
      Cachex.execute!(cache_store, fn cache ->
        case Cachex.exists?(cache, key) do
          {:ok, true} ->
            debug(key, "getting from cache")
            # warn(key, "getting from cache", trace_limit: 100)

            if opts[:check_env] == false or Config.env() != :dev do
              Cachex.get!(cache, key)
            else
              with {:error, e} <- Cachex.get!(cache, key) do
                error(
                  e,
                  "DEV convenience: An error was cached, so we'll ignore it and try running the function again"
                )

                val = maybe_apply_or_fun(module, fun, args, opts)
                Cachex.put!(cache, key, val, expire: expire)
                val
              end
            end

          {:ok, false} ->
            with {:error, _e} = ret <- maybe_apply_or_fun(module, fun, args, opts) do
              debug(key, "got an error, putting in cache with short TTL")
              Cachex.put!(cache, key, ret, expire: @error_cache_ttl)
              ret
            else
              ret ->
                debug(key, "fetched and putting in cache for next time")
                Cachex.put!(cache, key, ret, expire: expire)
                ret
            end

          {:error, e} ->
            error(e, "!! CACHE IS NOT WORKING !!")
            maybe_apply_or_fun(module, fun, args, opts)
        end
      end)
    else
      # warn(nil, "!! Cache not available, fallback to [re-]running the function without cache !!")

      maybe_apply_or_fun(module, fun, args, opts)

      # ^ this avoids compilation locks when cache is attempted to be used at compile time
    end
  rescue
    e in Cachex.ExecutionError ->
      error(e, "!! Error with the cache, fallback to [re-]running the function without cache !!")
      maybe_apply_or_fun(module, fun, args, opts)
  end

  @doc """
  Efficiently preloads and caches data for a list of objects.

  This function is useful when you need to fetch related data for a collection of objects (e.g. associations for a list of Ecto structs), and want to cache the results and minimize database queries.

  ## Parameters
    * `name` - A name for this type of preload, used as part of the cache key
    * `objects` - List of objects that need preloading
    * `fun` - A function that takes a list of IDs and returns a map of `{id, preloaded_data}`

  ## Examples

      iex> users = [%{id: "01BX5ZZKBKACTAV9WEVGEMMVRZ", name: "Alice"}, %{id: "01BX5ZZKBKACTAV9WEVGEMMVS0", name: "Bob"}]
      iex> loader = fn ids -> 
      ...>   # Simulating a database call that returns posts for users
      ...>   Enum.map(ids, fn id -> {id, ["Post by User"]} end) |> Map.new()
      ...> end
      iex> Bonfire.Common.Cache.cached_preloads_for_objects("user_posts", users, loader)
      %{"01BX5ZZKBKACTAV9WEVGEMMVRZ" => ["Post by User"], "01BX5ZZKBKACTAV9WEVGEMMVS0" => ["Post by User"]}
      
      # On subsequent calls, data will be retrieved from cache
  """
  def cached_preloads_for_objects(name, objects, fun, opts \\ [])
      when is_list(objects) and is_function(fun) do
    Cachex.execute!(opts[:cache_store] || default_cache_store(), fn cache ->
      maybe_cached =
        Enum.map(objects, fn obj ->
          id = Bonfire.Common.Types.uid(obj)
          key = "#{name}:{id}"

          with {:ok, ret} <- Cachex.get(cache, key) do
            {id, ret}
          end
        end)

      not_cached =
        maybe_cached
        |> Enum.filter(fn {_, v} -> is_nil(v) end)
        |> Enum.map(fn {id, _} -> id end)
        # |> debug("not yet cached")
        |> fun.()

      # |> debug("fetched")

      Enum.each(not_cached, fn {id, v} ->
        # TODO: longer cache TTL?
        Cachex.put(cache, "#{name}:#{id}", v)
      end)

      # cached = Enum.reject(maybe_cached, fn {_, v} -> is_nil(v) end)
      maybe_cached
      |> Map.new()
      |> Map.merge(not_cached)

      # |> debug("all")
    end)
  end

  @doc """
  Converts function arguments to a string representation for cache keys.

  For large argument lists, it creates a hash to keep keys at a reasonable length.

  ## Examples

      iex> Bonfire.Common.Cache.args_to_string(["hello"])
      "\\\"hello\\\""
      
      iex> Bonfire.Common.Cache.args_to_string("hello")
      "\\\"hello\\\""
      
      iex> Bonfire.Common.Cache.args_to_string([1, 2, 3, 4, 5])
      "1, 2, 3, 4, 5"

      iex> Bonfire.Common.Cache.args_to_string([0, [1, 2, 3, 4, 5]])
      "0, [1, 2, 3, 4, 5]"
      
      # For very long arguments, generates a hash
      > Bonfire.Common.Cache.args_to_string(Enum.to_list(1..100))
      # Returns a hashed string
  """
  def args_to_string(args) do
    case args
         |> args_transform()
         |> inspect()
         |> remove_list_brackets() do
      string_representation when byte_size(string_representation) > 36 ->
        "h:#{Bonfire.Common.Text.hash(string_representation)}"

      string_representation ->
        string_representation
    end
  end

  defp args_transform(%struct{id: id} = _struct) do
    {struct, id}
  end

  defp args_transform(%{id: id} = _map) do
    id
  end

  defp args_transform({key, value}) do
    {key, args_transform(value)}
  end

  defp args_transform(args) when is_list(args) or is_map(args) do
    Enum.map(args, &args_transform/1)
  end

  defp args_transform(value), do: value

  defp remove_list_brackets(<<"[", rest::binary>>) do
    binary_part(rest, 0, byte_size(rest) - 1)
  end

  defp remove_list_brackets(other), do: other

  defp maybe_apply_or_fun(module, fun, args, opts \\ [])

  defp maybe_apply_or_fun(module, fun, args, opts)
       when not is_nil(module) and is_atom(fun) and is_list(args) do
    Utils.maybe_apply(module, fun, args, opts)
  end

  defp maybe_apply_or_fun(_module, fun, no_args, _)
       when (is_function(fun) and is_nil(no_args)) or no_args == [] do
    apply(fun, [])
  end

  defp maybe_apply_or_fun(_module, fun, args, _) when is_function(fun) and is_list(args) do
    apply(fun, args)
  end

  @doc """
  Returns the default cache store to use.

  ## Examples

      iex> Bonfire.Common.Cache.default_cache_store()
      :bonfire_cache
  """
  defp default_cache_store do
    @default_store
  end
end
