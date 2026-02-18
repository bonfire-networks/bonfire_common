defmodule Bonfire.Common.Cache.HTTPPurge.Null do
  @moduledoc "No-op HTTP cache purge adapter (default). Used when no CDN/proxy is configured."

  @behaviour Bonfire.Common.Cache.HTTPPurge

  def bust_urls(_urls), do: :ok
  def bust_tags(_tags), do: :ok
end
