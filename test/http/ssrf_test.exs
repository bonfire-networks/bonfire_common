defmodule Bonfire.Common.HTTP.SSRFTest do
  @moduledoc """
  `Bonfire.Common.HTTP` is used for requests to URLs that can come from users or remote servers, so it must never reach a private or loopback address.

  The HTTP adapter is mocked and reports every request it gets. A test that expects a request to be refused checks that the mock never got it. Next to it, a test where a request is allowed checks that the mock does get it, which shows the request really would have been made. `ReqSSRF` has its own tests for which addresses count as private, so these only check that the check runs, and that the allowlist only covers the `host:port` it names.
  """
  use ExUnit.Case, async: false
  @moduletag :backend

  alias Bonfire.Common.HTTP

  setup do
    test_pid = self()

    Tesla.Mock.mock(fn env ->
      send(test_pid, {:hit, env.url})
      %Tesla.Env{status: 200, body: "ok"}
    end)

    :ok
  end

  test "a public address is requested" do
    # the test config resolves any name to a public address
    assert {:ok, %{status: 200}} = HTTP.get("http://example.com/page")
    assert_received {:hit, "http://example.com/page"}
  end

  test "a private address is never requested" do
    refute match?({:ok, _}, HTTP.get("http://10.0.0.1/page"))
    refute_received {:hit, _}
  end

  test "a request to a service configured by the admin (e.g. the search index) can opt out with `ssrf_check: false`" do
    assert {:ok, %{status: 200}} = HTTP.get("http://10.0.0.1:7700/indexes", [], ssrf_check: false)
    assert_received {:hit, "http://10.0.0.1:7700/indexes"}
  end

  test "the allowlist covers one port, not the whole host" do
    Process.put(:ssrf_allow_hosts, ["10.0.0.1:80"])

    assert {:ok, %{status: 200}} = HTTP.get("http://10.0.0.1/page")
    assert_received {:hit, "http://10.0.0.1/page"}

    refute match?({:ok, _}, HTTP.get("http://10.0.0.1:8080/page"))
    refute_received {:hit, _}
  end
end
