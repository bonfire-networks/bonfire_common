defmodule NebulexDiskAdapterTest do
  use ExUnit.Case, async: true
  import Bonfire.Common.Extend

  if module_exists?(Nebulex.Cache.EntryTest) do
    use_if_enabled(Nebulex.Cache.EntryTest)
    use_if_enabled(Nebulex.Cache.QueryableTest)

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
