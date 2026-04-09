defmodule Bonfire.Common.Cache.NebulexLocalCache do
  use Nebulex.Cache,
    otp_app: :bonfire_common,
    adapter: Nebulex.Adapters.Local
end
