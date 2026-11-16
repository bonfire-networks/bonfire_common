defmodule Bonfire.Common.HTTP.MetadataEndpointCheck do
  @moduledoc """
  Startup task (see `Bonfire.Common.StartupTasks`) that logs a warning when the cloud metadata address (169.254.169.254) accepts a connection from this server.

  The in-app SSRF guard (`Bonfire.Common.HTTP.SSRF`) refuses private addresses by name resolution, which cannot stop DNS rebinding: a name that resolves to a public address when checked and to a private one when connected. Outgoing traffic to private ranges and to the metadata address should therefore also be blocked at the network level (see the deploy docs). This check only tells an admin that the block is missing, it blocks nothing.

  Skipped in the test env. Configurable:

      config :bonfire_common, Bonfire.Common.HTTP.MetadataEndpointCheck,
        enabled: true,
        timeout: 1_000
  """
  @behaviour Bonfire.Common.StartupTask
  require Logger
  use Bonfire.Common.Config

  @host {169, 254, 169, 254}
  @port 80

  @impl Bonfire.Common.StartupTask
  def run do
    if Config.env() != :test and Config.get([__MODULE__, :enabled], true) do
      check()
    else
      :skipped
    end
  end

  @doc "Tries to connect to the metadata address with `connector` (a function of host, port and timeout in ms, returning `:ok` when the connection was accepted), and logs a warning when it was. Returns `:reachable` or `:unreachable`."
  def check(connector \\ &tcp_connect/3) do
    timeout = Config.get([__MODULE__, :timeout], to_timeout(second: 1))

    case connector.(@host, @port, timeout) do
      :ok ->
        Logger.warning(
          "This server can connect to the cloud metadata address (169.254.169.254). The SSRF guard cannot stop DNS rebinding, so block outgoing traffic from the app to private ranges and the metadata address at the network level (see the deploy docs)."
        )

        :reachable

      _ ->
        :unreachable
    end
  end

  defp tcp_connect(host, port, timeout) do
    case :gen_tcp.connect(host, port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      error ->
        error
    end
  end
end
