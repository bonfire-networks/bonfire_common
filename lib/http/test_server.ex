defmodule Bonfire.Common.HTTP.TestServer do
  @moduledoc """
  A real HTTP server on loopback, for testing code that makes its own requests (through Req, hackney, Finch…) which `Tesla.Mock` can't intercept, e.g. proving that a URL was or wasn't fetched.

  Used instead of `Bypass`, which only supports Ranch 1 while the app runs Ranch 2.
  """

  @doc """
  Starts a server under the current test's supervisor, so it stops with the test, and returns its port.

  `handler` receives each request's `Plug.Conn` and returns it with a response set or sent.
  """
  def start(handler) when is_function(handler, 1) do
    pid =
      ExUnit.Callbacks.start_supervised!(
        {Bandit,
         plug: {__MODULE__.Handler, handler},
         scheme: :http,
         ip: :loopback,
         port: 0,
         startup_log: false},
        id: make_ref()
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    port
  end

  defmodule Handler do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(handler), do: handler

    @impl true
    def call(conn, handler) do
      case handler.(conn) do
        %Plug.Conn{state: :set} = conn -> Plug.Conn.send_resp(conn)
        conn -> conn
      end
    end
  end
end
