defmodule Bonfire.Common.Cache.HTTPPurge do
  @moduledoc """
  Behaviour for HTTP cache purge adapters (Varnish, Nginx, Cloudflare, etc.).

  Adapters and credentials are resolved once at startup in
  `Bonfire.Common.RuntimeConfig` and stored in application config under
  `config :bonfire_common, Bonfire.Common.Cache.HTTPPurge`.

  """

  use Bonfire.Common.Config

  @doc """
  Purge a list of URL paths (or single URL path) from all configured HTTP cache adapters (fire-and-forget).

  ## Example

      bust_http_urls(["/posts/123", "/feed"])
  """
  def bust_http_urls(path) when is_binary(path), do: bust_http_urls([path])

  def bust_http_urls(urls) when is_list(urls) do
    for adapter <- Bonfire.Common.Cache.HTTPPurge.adapters() do
      Task.start(fn -> adapter.bust_urls(urls) end)
    end

    :ok
  end

  @doc """
  Purge all responses tagged with any of the given cache tags from all configured
  HTTP cache adapters (fire-and-forget).

  ## Example

      bust_http_tags(["post-123", "user-456"])
  """
  def bust_http_tags(tags) when is_list(tags) do
    for adapter <- Bonfire.Common.Cache.HTTPPurge.adapters() do
      Task.start(fn -> adapter.bust_tags(tags) end)
    end

    :ok
  end

  @doc "Purge one or more URL paths from the CDN/proxy cache."
  @callback bust_urls([String.t()]) :: :ok | {:error, term()}

  @doc "Purge all cached responses tagged with any of the given cache tags."
  @callback bust_tags([String.t()]) :: :ok | {:error, term()}

  @doc "Return the list of configured adapter modules."
  def adapters do
    Config.get([__MODULE__, :adapters], [__MODULE__.Null])
  end

  @doc "Return a config value for the given key."
  def config(key) do
    Config.get([__MODULE__, key])
  end
end
