defmodule Bonfire.Common.Cache.DiskLFUCache do
  use Nebulex.Cache,
    otp_app: :bonfire_common,
    adapter: Nebulex.Adapters.DiskLFU
end
