# WIP: Nebulex disk adapter based on https://hexdocs.pm/nebulex/creating-new-adapter.html and https://hexdocs.pm/cachex/Cachex.Disk.html 
defmodule Nebulex.DiskAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable

  alias Nebulex.DiskAdapter.DiskCacheHelper
  import DiskCacheHelper
  import Logger

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({DiskCacheHelper, []}, id: {DiskCacheHelper, __MODULE__})
    {:ok, child_spec, %{}}
  end

  @impl Nebulex.Adapter.Entry
  def get(adapter_meta, key, opts) do
    disk_get(adapter_meta, key, nil, opts)
  end

  @impl Nebulex.Adapter.Entry
  def get_all(adapter_meta, keys, opts) do
    Enum.map(keys, fn k ->
      case disk_get(adapter_meta, k, nil, opts) do
        nil -> nil
        v -> {k, v}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @impl Nebulex.Adapter.Entry
  def put(adapter_meta, key, value, ttl, :put_new, opts) do
    if get(adapter_meta, key, []) do
      false
    else
      put(adapter_meta, key, value, ttl, :put, opts)
    end
  end

  def put(adapter_meta, key, value, ttl, :replace, opts) do
    if get(adapter_meta, key, []) do
      put(adapter_meta, key, value, ttl, :put, opts)
    else
      false
    end
  end

  def put(adapter_meta, key, value, _ttl, _on_write, opts) do
    disk_put(adapter_meta, key, value, opts)
  end

  @impl Nebulex.Adapter.Entry
  def put_all(adapter_meta, entries, ttl, :put_new, opts) do
    if get_all(adapter_meta, Map.keys(entries), []) == %{} do
      put_all(adapter_meta, entries, ttl, :put, opts)
    else
      false
    end
  end

  def put_all(adapter_meta, entries, _ttl, _on_write, opts) do
    Enum.map(entries, fn {k, v} -> disk_put(adapter_meta, k, v, opts) end)
    true
  end

  @impl Nebulex.Adapter.Entry
  def delete(adapter_meta, key, opts) do
    # gotta pretend
    disk_delete(adapter_meta, key, opts) || :ok
  end

  @impl Nebulex.Adapter.Entry
  def take(adapter_meta, key, opts) do
    value = get(adapter_meta, key, opts)
    delete(adapter_meta, key, opts)
    value
  end

  @impl Nebulex.Adapter.Entry
  def update_counter(adapter_meta, key, amount, _ttl, default, opts) do
    value = (get(adapter_meta, key, opts) || default) + amount

    disk_put(adapter_meta, key, value, opts)

    value
  end

  @impl Nebulex.Adapter.Entry
  def has_key?(adapter_meta, key) do
    disk_list(adapter_meta[:cache])
    # |> IO.inspect(label: to_string(key))
    |> Enum.member?(key)
  end

  @impl Nebulex.Adapter.Entry
  def ttl(_adapter_meta, _key) do
    warn("TODO")
    nil
  end

  @impl Nebulex.Adapter.Entry
  def expire(_adapter_meta, _key, _ttl) do
    warn("TODO")
    true
  end

  @impl Nebulex.Adapter.Entry
  def touch(_adapter_meta, _key) do
    warn("TODO")
    true
  end

  @impl Nebulex.Adapter.Queryable
  def execute(adapter_meta, :delete_all, _query, opts) do
    # delete all
    deleted = execute(adapter_meta, :count_all, nil, [])

    # keys = disk_list(adapter_meta[:cache], opts)
    # Enum.map(keys, fn key -> delete(adapter_meta, key, opts) end)
    disk_clear(adapter_meta[:cache], opts)

    deleted
  end

  def execute(adapter_meta, :count_all, _query, opts) do
    # count
    keys = disk_list(adapter_meta[:cache], opts)
    length(keys)
    # |> IO.inspect(label: "count_all")
  end

  def execute(adapter_meta, :all, _query, opts) do
    # get all
    keys = disk_list(adapter_meta[:cache], opts)

    Enum.map(keys, fn key ->
      value = disk_get(adapter_meta, key, nil, opts)

      case Keyword.get(opts, :return) do
        :value ->
          value

        {:key, :value} ->
          {key, value}

        _ ->
          key
      end
    end)
  end

  @impl Nebulex.Adapter.Queryable
  def stream(_adapter_meta, :invalid_query, _opts) do
    raise Nebulex.QueryError, message: "invalid query", query: :invalid_query
  end

  def stream(adapter_meta, query, opts) do
    # TODO?
    execute(adapter_meta, :all, query, opts)
  end
end
