defmodule NebulexDiskAdapterTest do
  use ExUnit.Case, async: true

  if Bonfire.Common.Extend.module_exists?(Nebulex.Cache.EntryTest) do
    require Bonfire.Common.NebulexCacheTest
    Bonfire.Common.NebulexCacheTest.__using__([])

    alias Bonfire.Common.Cache.DiskCache, as: Cache

    setup do
      {:ok, _pid} = Cache.start_link()

      Nebulex.DiskAdapter.DiskCacheHelper.disk_clear(Cache)

      :ok

      on_exit(fn ->
        Nebulex.DiskAdapter.DiskCacheHelper.disk_clear(Cache)
      end)

      {:ok, cache: Cache, name: Cache}
    end
  end
end
