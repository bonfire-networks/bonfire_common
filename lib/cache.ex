defmodule Bonfire.Common.Cache do
  use Bonfire.Common.Utils

  @default_cache_ttl 1_000 * 60 * 60 * 6 # 6 hours
  @error_cache_ttl 1_000 * 60 * 5 # 5 min

  def maybe_apply_cached(fun, args, opts \\ [])
  def maybe_apply_cached(fun, args, opts) when is_function(fun) do
    opts
    # |> debug()
    |> Keyword.put_new_lazy(:cache_key, fn ->
      mod_fun = String.split(inspect(fun), " in ")
      |> List.last
      |> String.trim_trailing(">")

      "#{mod_fun}(#{satinise_args(args)})"
    end)
    |> do_maybe_apply_cached(nil, fun, args, ...)
  end
  def maybe_apply_cached({module, fun}, args, opts) when is_atom(module) and is_atom(fun) do
    opts
    |> Keyword.put_new_lazy(:cache_key, fn ->
      "#{String.trim_leading(Atom.to_string(module), "Elixir.")}.#{fun}(#{satinise_args(args)})"
    end)
    |> do_maybe_apply_cached(module, fun, args, ...)
  end

  defp do_maybe_apply_cached(module, fun, args, opts) do
    # debug(opts)
    key = opts[:cache_key]
    ttl = opts[:ttl] || @default_cache_ttl

    Cachex.execute!(cache_key(opts), fn(cache) ->
      case Cachex.exists?(cache, key) do
        {:ok, true} ->
          debug(key, "getting from cache")

          if Config.get(:env) !=:dev do
            Cachex.get!(cache, key)
          else
            with {:error, e} <- Cachex.get!(cache, key) do
              error(e, "An error was cached, so we'll ignore it and try running the function again")
              val = maybe_apply_or_fun(module, fun, args)
              Cachex.put!(cache, key, val, ttl: ttl)
              val
            end
          end

        {:ok, false} ->
          with {:error, e} = ret <- maybe_apply_or_fun(module, fun, args) do
            debug(key, "got an error, putting in cache with short TTL")
            Cachex.put!(cache, key, ret, ttl: @error_cache_ttl)
            ret
          else ret ->
            debug(key, "fetched and putting in cache for next time")
            Cachex.put!(cache, key, ret, ttl: ttl)
            ret
          end

        {:error, e} ->
          error(e, "!! CACHE IS NOT WORKING !!")
          maybe_apply_or_fun(module, fun, args)
      end
    end)
  end

  def cache_key(opts \\ []) do
    (opts[:cache_store] || :bonfire_cache)
  end

  def remove(key, opts \\ []) do
    cache_key(opts)
    |> Cachex.del(key)
    ~> debug("Removed from cache: #{key}")
  end

  def cached_preloads_for_objects(name, objects, fun) when is_list(objects) and is_function(fun) do
    Cachex.execute!(cache_key(), fn(cache) ->

      maybe_cached = Enum.map(objects, fn obj ->
        id = ulid(obj)
        key = "#{name}:{id}"

        with {:ok, ret} <- Cachex.get(cache, key) do
          {id, ret}
        end
      end)

      not_cached = maybe_cached
      |> Enum.filter(fn {_, v} -> is_nil(v) end)
      |> Enum.map(fn {id, _} -> id end)
      # |> debug("not yet cached")
      |> fun.()
      # |> debug("fetched")

      Enum.each(not_cached, fn {id, v} ->
        Cachex.put(cache, "#{name}:{id}", v) # TODO: longer cache TTL?
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
    |> inspect
  end

  def maybe_apply_or_fun(module, fun, args) when not is_nil(module) and is_atom(fun) do
    maybe_apply(module, fun, args)
  end
  def maybe_apply_or_fun(module, fun, args) when is_function(fun) do
    maybe_fun(fun, args)
  end

  def maybe_fun(fun, [arg]) when is_function(fun) do
    fun.(arg)
  end
  def maybe_fun(fun, [arg1, arg2]) when is_function(fun) do
    fun.(arg1, arg2)
  end
  def maybe_fun(fun, [arg1, arg2, arg3]) when is_function(fun) do
    fun.(arg1, arg2, arg3)
  end
  def maybe_fun(fun, [arg1, arg2, arg3, arg4]) when is_function(fun) do
    fun.(arg1, arg2, arg3, arg4)
  end
  def maybe_fun(fun, [arg1, arg2, arg3, arg4, arg5]) when is_function(fun) do
    fun.(arg1, arg2, arg3, arg4, arg5)
  end
  def maybe_fun(fun, arg) when is_function(fun) do
    fun.(arg)
  end

end
