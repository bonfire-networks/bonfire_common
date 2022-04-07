defmodule Bonfire.Web.Plugs.ActivityPub do
  import Plug.Conn
  import Where

  def init(_opts), do: nil

  def call(%{req_headers: req_headers} = conn, opts) do
    with_headers(conn, req_headers |> Map.new, opts)
  end

  def call(conn, _opts) do
    conn
  end

  def with_headers(%{params: params} = conn, %{"accept" => "application/ld+json"<>_}, _opts)  do
    maybe_redirect(conn)
  end

  def with_headers(%{params: params} = conn, %{"accept" => "application/activity+json"<>_}, _opts)  do
    maybe_redirect(conn)
  end

  def with_headers(%{params: params} = conn, %{"accept" => "application/json"<>_}, _opts)  do
    maybe_redirect(conn)
  end

  def with_headers(conn, _, _opts) do
    conn
  end

  def maybe_redirect(%{params: params} = conn) when not is_nil(params) do
    request_url = request_url(conn)
    case Bonfire.Common.URIs.canonical_url(params) do
      url when is_binary(url) and url != request_url ->
        conn
        |> Phoenix.Controller.redirect(external: url)
        |> halt()
      _ ->
        conn
    end
  end

  def maybe_redirect(conn) do
    conn
  end
end
