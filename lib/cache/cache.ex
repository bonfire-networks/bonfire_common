defmodule Bonfire.Common.Cache do
  @moduledoc "Helpers for caching data and operations"

  use Decorator.Define, cache: 0
  use Untangle
  use Arrows
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Config

  # 6 hours
  @default_cache_ttl 1_000 * 60 * 60 * 6
  # 5 min
  @error_cache_ttl 1_000 * 60 * 5

  @default_store :bonfire_cache

  # TODO: explore using Decorator lib to support decorating functions to cache them
  # def cache(fn_body, context) do
  # end

  def put(key, value, opts \\ []) do
    Cachex.put(cache_store(opts), key, value, opts |> Keyword.put_new(:ttl, @default_cache_ttl))
    value
  end

  def get(key, opts \\ []), do: Cachex.get(cache_store(opts), key)

  def get!(key, opts \\ []) do
    case get(key, opts) do
      {:ok, val} -> val
      _ -> nil
    end
  end

  @doc "Takes a function (or module and function names) and a set of arguments for that function, and tries to fetch the previous result of running that function from the in-memory cache, using the MFA (module name/function name/arguments used) to generate the cache key. If it's not in the cache, it executes the function, and caches and returns the result."
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

  def cache_store(opts \\ []) do
    opts[:cache_store] || @default_store
  end

  @doc "It removes the result of a given function from the cache."
  def reset(fun, args, opts \\ []) do
    key_for_call(fun, args)
    |> remove(opts)
  end

  @doc "It removes the entry associated with a key from the cache."
  def remove(key, opts \\ []) do
    cache_store(opts)
    |> Cachex.del(key)
    ~> debug("Removed from cache: #{key}")
  end

  def remove_all(opts \\ []) do
    store = cache_store(opts)

    Cachex.clear(store)
    ~> debug("Cleared cache: #{store}")
  end

  defp key_for_call(fun, args) when is_function(fun) do
    mod_fun =
      String.split(inspect(fun), " in ")
      |> List.last()
      |> String.trim_trailing(">")

    "#{mod_fun}(#{satinise_args(args)})"
  end

  defp key_for_call({module, fun}, args)
       when is_atom(module) and is_atom(fun) do
    "#{String.trim_leading(Atom.to_string(module), "Elixir.")}.#{fun}(#{satinise_args(args)})"
  end

  defp do_maybe_apply_cached(module \\ nil, fun, args, opts) do
    # debug(opts)
    key = opts[:cache_key]
    ttl = opts[:ttl] || @default_cache_ttl
    cache_store = cache_store(opts)

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
                Cachex.put!(cache, key, val, ttl: ttl)
                val
              end
            end

          {:ok, false} ->
            with {:error, _e} = ret <- maybe_apply_or_fun(module, fun, args, opts) do
              debug(key, "got an error, putting in cache with short TTL")
              Cachex.put!(cache, key, ret, ttl: @error_cache_ttl)
              ret
            else
              ret ->
                debug(key, "fetched and putting in cache for next time")
                Cachex.put!(cache, key, ret, ttl: ttl)
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

  def cached_preloads_for_objects(name, objects, fun)
      when is_list(objects) and is_function(fun) do
    Cachex.execute!(cache_store(), fn cache ->
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

  defp satinise_args(args) do
    Enum.map(args, fn
      %{id: id} -> id
      other -> other
    end)
    |> inspect()
  end

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
end
