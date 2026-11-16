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

  describe "a name that resolves to both a public and a private address" do
    # the resolver is called once per family: `:inet` answers A records, `:inet6` AAAA records
    defp resolve_with(a, aaaa) do
      previous = Application.get_env(:bonfire_common, :ssrf)

      Application.put_env(:bonfire_common, :ssrf,
        resolver: fn
          _name, :inet, _timeout -> a
          _name, :inet6, _timeout -> aaaa
        end
      )

      on_exit(fn -> Application.put_env(:bonfire_common, :ssrf, previous) end)
    end

    test "is requested when every address is public (control)" do
      resolve_with(
        {:ok, [{93, 184, 216, 34}]},
        {:ok, [{0x2606, 0x2800, 0x220, 1, 0x248, 0x1893, 0x25C8, 0x1946}]}
      )

      assert {:ok, %{status: 200}} = HTTP.get("http://dual.example.com/page")
      assert_received {:hit, "http://dual.example.com/page"}
    end

    test "is never requested when its AAAA record is a private address" do
      resolve_with({:ok, [{93, 184, 216, 34}]}, {:ok, [{0, 0, 0, 0, 0, 0, 0, 1}]})

      refute match?({:ok, _}, HTTP.get("http://dual.example.com/page"))
      refute_received {:hit, _}
    end

    test "is never requested when its AAAA record is an IPv4-mapped private address" do
      resolve_with({:ok, [{93, 184, 216, 34}]}, {:ok, [{0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0001}]})

      refute match?({:ok, _}, HTTP.get("http://dual.example.com/page"))
      refute_received {:hit, _}
    end
  end

  test "the allowlist covers one port, not the whole host" do
    Process.put(:ssrf_allow_hosts, ["10.0.0.1:80"])

    assert {:ok, %{status: 200}} = HTTP.get("http://10.0.0.1/page")
    assert_received {:hit, "http://10.0.0.1/page"}

    refute match?({:ok, _}, HTTP.get("http://10.0.0.1:8080/page"))
    refute_received {:hit, _}
  end
end
