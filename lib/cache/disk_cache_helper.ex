defmodule Nebulex.DiskAdapter.DiskCacheHelper do
  @moduledoc "WIP: Nebulex disk adapter based on https://hexdocs.pm/nebulex/creating-new-adapter.html and https://hexdocs.pm/cachex/Cachex.Disk.html"
  use GenServer
  import Logger

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, [], options)
  end

  defp root_path(opts) do
    opts[:cache_dir] || :filename.basedir(:user_cache, ~c"bonfire_cache")
  end

  def cache_path(key, adapter_meta, opts) do
    # IO.inspect(adapter_meta) # e.g: %{pid: #PID<0.7179.0>, cache: Bonfire.Common.Cache.DiskCache}

    Path.join([
      root_path(opts),
      to_string(adapter_meta[:cache] || "unknown"),
      :erlang.term_to_binary(key)
      |> Base.encode16()
    ])
  end

  def disk_put(adapter_meta, key, data, opts) do
    path = cache_path(key, adapter_meta, opts)

    with {:ok, _} <- write_cache(path, data) do
      true
    else
      e ->
        warn("Could not write file #{path} for key #{key}: #{inspect(e)}")
        false
    end
  end

  defp write_cache(path, data) do
    File.mkdir_p!(Path.dirname(path))
    Cachex.Disk.write(data, path)
  end

  def disk_list(cache_module \\ nil, opts \\ [])

  def disk_list(cache_module, opts) when is_atom(cache_module) and not is_nil(cache_module) do
    Path.join(root_path(opts), to_string(cache_module))
    |> do_disk_list()
  end

  def disk_list(_, opts) do
    root_path(opts)
    |> do_disk_list()
  end

  defp do_disk_list(path) do
    path
    |> File.ls!()
    |> Enum.map(fn path ->
      with {:ok, bin} <- Base.decode16(path) do
        :erlang.binary_to_term(bin)
      else
        e ->
          warn("Could not decode key from file #{path}: #{inspect(e)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    # |> IO.inspect(label: "disk_list")
  end

  def disk_get(adapter_meta, key, fun, opts) do
    path = cache_path(key, adapter_meta, opts)

    with {:ok, data} <- file_load(path) do
      data
      |> maybe_fun(fun)
    else
      e ->
        warn("Could not read file #{path} for key #{key}: #{inspect(e)}")
        nil
    end
  end

  defp file_load(path) do
    path |> Cachex.Disk.read()
  end

  # def disk_stream(adapter_meta, key, fun, opts) do
  #   path = cache_path(key, adapter_meta, opts) 
  #   with {:ok, data} <- file_stream(path, opts) do
  #     data
  #     |> maybe_fun(fun)
  #   else e ->
  #     warn("Could not read file #{path} for key #{key}: #{inspect e}")
  #     nil
  #   end
  # end

  # defp file_stream(path, options \\ []) when is_binary(path) and is_list(options) do
  #   trusted = Options.get(options, :trusted, &is_boolean/1, true)

  #   path
  #   |> File.stream!()
  #   |> :erlang.binary_to_term((trusted && []) || [:safe])
  #   |> wrap(:ok)
  # rescue
  #   _ -> error(:unreachable_file)
  # end

  def disk_delete(adapter_meta, key, opts) do
    path = cache_path(key, adapter_meta, opts)

    with :ok <- File.rm(path) do
      :ok
    else
      e ->
        warn("Could not delete file #{path} for key #{key}: #{inspect(e)}")
        false
    end
  end

  def disk_clear(cache_module \\ nil, opts \\ [])

  def disk_clear(cache_module, opts) when is_atom(cache_module) and not is_nil(cache_module) do
    path = Path.join(root_path(opts), to_string(cache_module))
    File.rm_rf!(path)
    File.mkdir_p!(path)
  end

  def disk_clear(_, opts) do
    path = root_path(opts)
    File.rm_rf!(path)
    File.mkdir_p!(path)
  end

  defp maybe_fun(data, fun) when is_function(fun, 1), do: fun.(data)
  defp maybe_fun(data, _), do: data
end
