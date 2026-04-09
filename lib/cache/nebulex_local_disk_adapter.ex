# defmodule Bonfire.Common.Nebulex.LocalDiskAdapter do
#   @moduledoc "Nebulex disk adapter based on https://hexdocs.pm/nebulex/creating-new-adapter.html and https://hexdocs.pm/cachex/Cachex.Disk.html"

#   @behaviour Nebulex.Adapter
#   @behaviour Nebulex.Adapter.KV
#   @behaviour Nebulex.Adapter.Queryable

#   alias Bonfire.Common.Nebulex.LocalDiskAdapter.DiskCacheHelper
#   import DiskCacheHelper
#   import Untangle

#   @impl Nebulex.Adapter
#   defmacro __before_compile__(_env), do: :ok

#   @impl Nebulex.Adapter
#   def init(opts) do
#     child_spec = Supervisor.child_spec({DiskCacheHelper, []}, id: {DiskCacheHelper, __MODULE__})
#     {:ok, [child_spec], Map.new(opts)}
#   end

#   # ---------------------------------------------------------------------------
#   # Nebulex.Adapter.KV callbacks (v3)
#   # ---------------------------------------------------------------------------

#   @impl Nebulex.Adapter.KV
#   def fetch(adapter_meta, key, _opts) do
#     case disk_get(adapter_meta, key, nil, []) do
#       nil -> {:error, %Nebulex.KeyError{key: key}}
#       value -> {:ok, value}
#     end
#   end

#   @impl Nebulex.Adapter.KV
#   def put(adapter_meta, key, value, :put_new, _ttl, _keep_ttl, opts) do
#     case disk_get(adapter_meta, key, nil, opts) do
#       nil ->
#         disk_put(adapter_meta, key, value, opts)
#         {:ok, true}

#       _ ->
#         {:ok, false}
#     end
#   end

#   def put(adapter_meta, key, value, :replace, _ttl, _keep_ttl, opts) do
#     case disk_get(adapter_meta, key, nil, opts) do
#       nil ->
#         {:ok, false}

#       _ ->
#         disk_put(adapter_meta, key, value, opts)
#         {:ok, true}
#     end
#   end

#   def put(adapter_meta, key, value, _on_write, _ttl, _keep_ttl, opts) do
#     disk_put(adapter_meta, key, value, opts)
#     {:ok, true}
#   end

#   @impl Nebulex.Adapter.KV
#   def put_all(adapter_meta, entries, :put_new, _ttl, opts) do
#     if disk_list(adapter_meta[:cache]) |> Enum.any?(&Map.has_key?(entries, &1)) do
#       {:ok, false}
#     else
#       Enum.each(entries, fn {k, v} -> disk_put(adapter_meta, k, v, opts) end)
#       {:ok, true}
#     end
#   end

#   def put_all(adapter_meta, entries, _on_write, _ttl, opts) do
#     Enum.each(entries, fn {k, v} -> disk_put(adapter_meta, k, v, opts) end)
#     {:ok, true}
#   end

#   @impl Nebulex.Adapter.KV
#   def delete(adapter_meta, key, opts) do
#     disk_delete(adapter_meta, key, opts)
#     :ok
#   end

#   @impl Nebulex.Adapter.KV
#   def take(adapter_meta, key, opts) do
#     case disk_get(adapter_meta, key, nil, opts) do
#       nil ->
#         {:error, %Nebulex.KeyError{key: key}}

#       value ->
#         disk_delete(adapter_meta, key, opts)
#         {:ok, value}
#     end
#   end

#   @impl Nebulex.Adapter.KV
#   def update_counter(adapter_meta, key, amount, default, _ttl, opts) do
#     value = (disk_get(adapter_meta, key, nil, opts) || default) + amount
#     disk_put(adapter_meta, key, value, opts)
#     {:ok, value}
#   end

#   @impl Nebulex.Adapter.KV
#   def has_key?(adapter_meta, key, _opts) do
#     result =
#       disk_list(adapter_meta[:cache])
#       |> Enum.member?(key)

#     {:ok, result}
#   end

#   @impl Nebulex.Adapter.KV
#   def ttl(_adapter_meta, _key, _opts) do
#     warn("TODO")
#     {:ok, nil}
#   end

#   @impl Nebulex.Adapter.KV
#   def expire(_adapter_meta, _key, _ttl, _opts) do
#     warn("TODO")
#     {:ok, true}
#   end

#   @impl Nebulex.Adapter.KV
#   def touch(_adapter_meta, _key, _opts) do
#     warn("TODO")
#     {:ok, true}
#   end

#   # ---------------------------------------------------------------------------
#   # Nebulex.Adapter.Queryable callbacks (v3)
#   # ---------------------------------------------------------------------------

#   @impl Nebulex.Adapter.Queryable
#   def execute(adapter_meta, %{op: :delete_all}, _opts) do
#     deleted = length(disk_list(adapter_meta[:cache]))
#     disk_clear(adapter_meta[:cache], [])
#     {:ok, deleted}
#   end

#   def execute(adapter_meta, %{op: :count_all}, _opts) do
#     {:ok, length(disk_list(adapter_meta[:cache]))}
#   end

#   def execute(adapter_meta, %{op: :get_all, select: select}, opts) do
#     keys = disk_list(adapter_meta[:cache])

#     result =
#       Enum.map(keys, fn key ->
#         value = disk_get(adapter_meta, key, nil, opts)

#         case select do
#           :value -> value
#           {:key, :value} -> {key, value}
#           _ -> key
#         end
#       end)

#     {:ok, result}
#   end

#   @impl Nebulex.Adapter.Queryable
#   def stream(adapter_meta, query_meta, opts) do
#     case execute(adapter_meta, query_meta, opts) do
#       {:ok, list} -> {:ok, Stream.iterate(list, & &1) |> Stream.take(1) |> Stream.flat_map(& &1)}
#       error -> error
#     end
#   end
# end
