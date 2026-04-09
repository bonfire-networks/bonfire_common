defmodule Bonfire.Common.Cache.SimpleDiskCache do
  @moduledoc """
  A plain filesystem-based cache backend for `Bonfire.Common.Cache.Backend`.

  Uses the same `(key, opts)` API as Nebulex modules so it is a drop-in alternative
  to `DiskLFUCache` for the `cache_backend` or `disk_cache_backend` config keys in
  `MaybeStaticGeneratorPlug`.

  Keys are URL paths. Values are written as `index.html` files under `opts[:root_path]`.

  Supports `return: :path` to return the file path instead of reading the body —
  callers can pass the path directly to `Plug.Conn.send_file/5` for zero-copy serving.
  """

  @doc """
  Get a cached value.

  With `return: :path`, returns `{:ok, path}` if the file exists (for use with
  `Plug.Conn.send_file/5`) rather than reading the body into memory.
  """
  def get(key, opts) do
    path = disk_path(key, opts)

    if opts[:return] == :path do
      if File.exists?(path), do: {:ok, path}, else: {:ok, nil}
    else
      case File.read(path) do
        {:ok, body} -> {:ok, body}
        _ -> {:ok, nil}
      end
    end
  end

  @doc "Write a value to disk. Creates parent directories as needed."
  def put(key, val, opts) do
    path = disk_path(key, opts)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, val)
    end
  end

  @doc "Delete the cached file for a key."
  def delete(key, opts), do: File.rm(disk_path(key, opts))

  @doc "Check whether a cached file exists."
  def has_key?(key, opts), do: {:ok, File.exists?(disk_path(key, opts))}

  @doc """
  Returns the full disk path for a given URL key.

  Reads `opts[:root_path]` as the root. Callers must pass this opt; there is no
  default here to avoid a dependency on `StaticGenerator` from `bonfire_common`.
  """
  def disk_path(key, opts) do
    root = opts[:root_path] || raise ArgumentError, "SimpleDiskCache requires opts[:root_path]"
    Path.join([root, String.trim_leading(key, "/"), "index.html"])
  end
end
