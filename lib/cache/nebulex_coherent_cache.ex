defmodule Bonfire.Common.Cache.NebulexCoherentCache do
  use Nebulex.Cache,
    otp_app: :bonfire_common,
    adapter: Nebulex.Adapters.Coherent
end
