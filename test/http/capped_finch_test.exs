defmodule Bonfire.Common.HTTP.CappedFinchTest do
  @moduledoc """
  A server that answers with a huge body must not get all of it read: `Bonfire.Common.HTTP.CappedFinch` stops reading at the size limit and closes the connection, or refuses at once when the headers declare a body over the limit. The server here is a real local socket that sends until the client closes (or 256 MB are sent), so what it managed to send says how much the client read: far less than what it had to send.
  """
  use ExUnit.Case, async: false
  @moduletag :backend

  alias Bonfire.Common.HTTP.CappedFinch

  @cap 1_000_000
  @chunk_size 64 * 1024
  @max_to_send 256 * 1024 * 1024
  # socket buffers on both sides hold a few MB; far under what the server was ready to send
  @max_sent_before_close 24 * 1024 * 1024

  setup do
    finch = :"capped_finch_test_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: finch})

    client = Tesla.client([], {CappedFinch, name: finch, max_body_bytes: @cap})
    {:ok, client: client}
  end

  # answers the first request with `head` and then, until the client closes the connection, with chunks of 64 KB (or `body`, if given, once)
  defp serve(head, body \\ nil) do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        reuseaddr: true,
        send_timeout: 5_000,
        send_timeout_close: true
      ])

    {:ok, port} = :inet.port(listen)
    test_pid = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)
      :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\n" <> head <> "\r\n")

      sent =
        if body do
          :gen_tcp.send(socket, body)
          byte_size(body)
        else
          send_chunks(socket, 0)
        end

      send(test_pid, {:server_sent, sent})
      :gen_tcp.close(socket)
      :gen_tcp.close(listen)
    end)

    "http://127.0.0.1:#{port}/"
  end

  defp send_chunks(_socket, sent) when sent >= @max_to_send, do: sent

  defp send_chunks(socket, sent) do
    chunk = String.duplicate("a", @chunk_size)
    framed = Integer.to_string(@chunk_size, 16) <> "\r\n" <> chunk <> "\r\n"

    case :gen_tcp.send(socket, framed) do
      :ok -> send_chunks(socket, sent + @chunk_size)
      {:error, _closed} -> sent
    end
  end

  test "a body under the limit is read whole (control)", %{client: client} do
    url = serve("content-length: 5\r\n", "hello")

    assert {:ok, %{status: 200, body: "hello"}} = Tesla.get(client, url)
  end

  test "a body with no length that goes on past the limit is read only up to it", %{
    client: client
  } do
    url = serve("transfer-encoding: chunked\r\n")

    assert {:error, :body_too_large} = Tesla.get(client, url)

    assert_receive {:server_sent, sent}, 10_000

    assert sent < @max_sent_before_close,
           "the server could send #{div(sent, 1024 * 1024)} MB before the client closed the connection"
  end

  test "a content-length over the limit is refused before the body is read", %{client: client} do
    url = serve("content-length: #{@max_to_send}\r\n")

    assert {:error, :body_too_large} = Tesla.get(client, url)

    assert_receive {:server_sent, sent}, 10_000

    assert sent < @max_sent_before_close,
           "the server could send #{div(sent, 1024 * 1024)} MB before the client closed the connection"
  end
end
