defmodule Bonfire.Common.HTTP.SSRF do
  @moduledoc """
  Tesla middleware (and, with `attach/1`, a `Req` plugin) that refuses requests to private, loopback and other reserved addresses (Server-Side Request Forgery), using `ReqSSRF.check/2`. If a redirect middleware is added to the client, plug this after it, so every hop is checked.

  A request for a service the admin configured (e.g. the search index) can skip the check with the `ssrf_check: false` option. Never pass it for a URL that comes from users or remote servers.

  A `host:port` in the `:ssrf_allow_hosts` config of `:bonfire_common` (or set with `Process.put/2` in a test) skips the check for that request only, e.g. for another instance in a local multi-instance setup. Extra `ReqSSRF` options can be set in the `:ssrf` config.
  """
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    # `ssrf_check: false` is for services the admin configured (e.g. the search index, usually on a private address), never for URLs from users or remote servers
    with false <- env.opts[:ssrf_check] == false,
         {:error, reason} <- check(env.url) do
      {:error, {:ssrf, reason}}
    else
      _ -> Tesla.run(env, next)
    end
  end

  @doc """
  Checks a URL the way this middleware does, for clients that don't go through `Bonfire.Common.HTTP` (e.g. libraries with their own HTTP client). Returns `:ok` or `{:error, reason}`.
  """
  def check(url) do
    %URI{host: host, port: port} = uri = URI.parse(url)

    if "#{host}:#{port}" in allow_hosts() do
      :ok
    else
      ReqSSRF.check(uri, Application.get_env(:bonfire_common, :ssrf, []))
    end
  end

  @doc """
  A `Req` plugin that applies `check/1` to a request, on the first request and on every redirect hop (Req runs request steps again for each), e.g. `Req.get(url, plugins: [&Bonfire.Common.HTTP.SSRF.attach/1])`. A refused request returns `{:error, %ReqSSRF.BlockedError{}}`.
  """
  def attach(%Req.Request{} = request),
    do: Req.Request.append_request_steps(request, bonfire_ssrf_check: &check_req/1)

  defp check_req(request) do
    case check(request.url) do
      :ok ->
        request

      {:error, reason} ->
        Req.Request.halt(request, %ReqSSRF.BlockedError{url: request.url, reason: reason})
    end
  end

  defp allow_hosts,
    do:
      ProcessTree.get(:ssrf_allow_hosts) ||
        Application.get_env(:bonfire_common, :ssrf_allow_hosts, [])
end
