defmodule Bonfire.Common.HTTP.MetadataEndpointCheckTest do
  @moduledoc "A server that can connect to the cloud metadata address gets a warning at boot, as the in-app SSRF guard cannot stop DNS rebinding."
  use ExUnit.Case, async: true
  @moduletag :backend

  import ExUnit.CaptureLog
  alias Bonfire.Common.HTTP.MetadataEndpointCheck

  test "a connection accepted by the metadata address logs a warning" do
    log =
      capture_log(fn ->
        assert MetadataEndpointCheck.check(fn _host, _port, _timeout -> :ok end) == :reachable
      end)

    assert log =~ "169.254.169.254"
    assert log =~ "network level"
  end

  test "a refused or timed out connection logs nothing" do
    log =
      capture_log(fn ->
        assert MetadataEndpointCheck.check(fn _, _, _ -> {:error, :timeout} end) == :unreachable
      end)

    refute log =~ "169.254.169.254"
  end

  test "the connector is asked for the metadata address on port 80 within a second" do
    test = self()

    MetadataEndpointCheck.check(fn host, port, timeout ->
      send(test, {:asked, host, port, timeout})
      {:error, :econnrefused}
    end)

    assert_received {:asked, {169, 254, 169, 254}, 80, timeout}
    assert timeout <= 1_000
  end

  test "it does nothing in the test env" do
    assert MetadataEndpointCheck.run() == :skipped
  end
end
