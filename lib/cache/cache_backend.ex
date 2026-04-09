defmodule Bonfire.Common.Cache.Backend do
  @moduledoc """
  Low-level dispatch layer between `Bonfire.Common.Cache` and the underlying cache backend.

  Supports three types of backends via pattern-matching on the first argument:
  - `Cachex` (the module) — delegates to the Cachex API using `opts[:cache_store]` (default `:bonfire_cache`)
  - `SimpleDiskCache` — plain filesystem backend; see `Bonfire.Common.Cache.SimpleDiskCache`
  - Any Nebulex cache module (e.g. `Bonfire.Common.Cache.NebulexLocalCache`) — delegates to the Nebulex API

  All functions accept an `opts` keyword list. Relevant keys include:
  - `:cache_store` — Cachex store name atom (default `:bonfire_cache`; ignored for other backends)
  - `:expire` — TTL in milliseconds (used for `put/4`)
  - `:return` — set to `:path` to get a filesystem path instead of reading the value body into memory;
    supported by `SimpleDiskCache` (returns actual file path) and Nebulex `DiskLFUCache` (returns temp symlink).
    Useful for passing the path to `Plug.Conn.send_file/5` for zero-copy serving.
  """

  alias Bonfire.Common.Cache.SimpleDiskCache

  @default_store :bonfire_cache

  # Internal keys that must not be forwarded to Nebulex (it validates opts strictly)
  @bonfire_opts [
    :cache_backend,
    :cache_store,
    :default,
    :on_error,
    :check_env,
    :return,
    :root_path
  ]

  defp nebulex_opts(opts), do: Keyword.drop(opts, @bonfire_opts)

  @doc "Get a value by key. Pass `return: :path` to get a filesystem path for `send_file/5` instead of reading the body into memory (supported by `SimpleDiskCache` and Nebulex `DiskLFUCache`)."
  def get(Cachex, key, opts), do: Cachex.get(opts[:cache_store] || @default_store, key)
  def get(SimpleDiskCache, key, opts), do: SimpleDiskCache.get(key, opts)

  def get(mod, key, opts) do
    # Translate return: :path to return: :symlink for Nebulex DiskLFU
    extra = if opts[:return] == :path, do: [return: :symlink], else: []

    case mod.get(key, opts[:default], nebulex_opts(opts) ++ extra) do
      {:ok, "term:" <> bin} -> {:ok, :erlang.binary_to_term(bin)}
      other -> other
    end
  end

  @doc "Put a value with optional TTL (`opts[:expire]` in ms). Async by default — returns `:ok` immediately and writes in a background task. Pass `async: false` to block until the write completes (e.g. in tests)."
  def put(backend, key, val, opts) do
    if opts[:async] == false do
      do_put(backend, key, val, opts)
    else
      Task.start(fn -> do_put(backend, key, val, opts) end)
      :ok
    end
  end

  defp do_put(Cachex, key, val, opts),
    do:
      Cachex.put(
        opts[:cache_store] || @default_store,
        key,
        val,
        Keyword.drop(opts, @bonfire_opts)
      )

  defp do_put(SimpleDiskCache, key, val, opts), do: SimpleDiskCache.put(key, val, opts)

  defp do_put(mod, key, val, opts) do
    nebulex_put_opts = if opts[:expire], do: [ttl: opts[:expire]], else: []

    mod.put!(
      key,
      if(is_binary(val), do: val, else: "term:" <> :erlang.term_to_binary(val)),
      nebulex_put_opts
    )
  end

  @doc "Delete a single key."
  def delete(Cachex, key, opts), do: Cachex.del(opts[:cache_store] || @default_store, key)
  def delete(SimpleDiskCache, key, opts), do: SimpleDiskCache.delete(key, opts)
  def delete(mod, key, opts), do: mod.delete!(key, nebulex_opts(opts))

  @doc "Clear all entries."
  def clear(Cachex, opts), do: Cachex.clear(opts[:cache_store] || @default_store)
  def clear(SimpleDiskCache, opts), do: File.rm_rf(opts[:root_path])
  def clear(mod, _opts), do: mod.delete_all!()

  @doc "Check whether a key exists. Returns `{:ok, bool}`."
  def has_key?(Cachex, key, opts), do: Cachex.exists?(opts[:cache_store] || @default_store, key)
  def has_key?(SimpleDiskCache, key, opts), do: SimpleDiskCache.has_key?(key, opts)
  def has_key?(mod, key, opts), do: mod.has_key?(key, nebulex_opts(opts))

  @doc "Execute a function atomically within the cache. Uses `Cachex.execute!` or `Nebulex.transaction/2`."
  def execute_transaction(Cachex, _key, fun, opts),
    do: Cachex.execute!(opts[:cache_store] || @default_store, fun)

  def execute_transaction(SimpleDiskCache, _key, fun, opts),
    do: raise("SimpleDiskCache does not currently support transactions")

  def execute_transaction(mod, key, fun, opts) do
    case mod.transaction(fun, Keyword.put(nebulex_opts(opts), :keys, [key])) do
      {:ok, result} -> result
      other -> other
    end
  end
end
