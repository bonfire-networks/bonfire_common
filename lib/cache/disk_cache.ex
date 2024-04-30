defmodule Bonfire.Common.Cache.DiskCache do
  use Nebulex.Cache,
    otp_app: :bonfire_common,
    adapter: Nebulex.DiskAdapter
end
