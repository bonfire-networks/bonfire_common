defmodule Bonfire.Web.Plugs.ActivityPub do
  import Plug.Conn

  def init(_opts), do: nil

  def call(%{req_headers: req_headers} = conn, opts) do
    with_headers(conn, req_headers |> Map.new, opts)
  end

  def call(conn, _opts) do
    conn
  end

  def with_headers(conn, %{"accept" => "application/activity+json"}, _opts) do
    url =
    case Bonfire.Common.URIs.canonical_url(conn.params) do
      url when is_binary(url) ->
        conn
        |> Phoenix.Controller.redirect(external: url)
        |> halt()
      _ ->
        conn
    end
  end

  def with_headers(conn, _, _opts) do
    conn
  end

end
