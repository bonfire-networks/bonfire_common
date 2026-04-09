defmodule NebulexDiskAdapterTest do
  use ExUnit.Case, async: true
  import Bonfire.Common.Extend

  if module_exists?(Nebulex.Cache.EntryTest) do
    use_if_enabled(Nebulex.Cache.EntryTest)
    use_if_enabled(Nebulex.Cache.QueryableTest)

    alias Bonfire.Common.Cache.LocalDiskCache, as: Cache

    setup do
      {:ok, _pid} = Cache.start_link()

      Bonfire.Common.Nebulex.LocalDiskAdapter.DiskCacheHelper.disk_clear(Cache)

      :ok

      on_exit(fn ->
        Bonfire.Common.Nebulex.LocalDiskAdapter.DiskCacheHelper.disk_clear(Cache)
      end)

      {:ok, cache: Cache, name: Cache}
    end
  end
end
