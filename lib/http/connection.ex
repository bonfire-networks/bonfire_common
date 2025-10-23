defmodule Bonfire.Common.HTTP.Connection do
  @moduledoc """
  Specifies connection options for HTTP requests
  """
  use Bonfire.Common.Config
  import Bonfire.Common.Opts

  def new(opts \\ []) do
    adapter = Application.get_env(:tesla, :adapter) || {Tesla.Adapter.Finch, name: Bonfire.Finch}

    Tesla.client(
      [Tesla.Middleware.Telemetry],
      adapter_options(adapter, Keyword.get(opts, :adapter, []))
    )
  end

  def adapter_options(adapter \\ Tesla.Adapter.Hackney, opts)

  def adapter_options(Tesla.Adapter.Hackney, opts) do
    opts = to_options(opts)

    adapter_options = Config.get([:http, :adapter_options]) || []
    proxy_url = Config.get([:http, :proxy_url])

    base_options = [
      connect_timeout: 10_000,
      recv_timeout: 20_000,
      follow_redirect: true,
      pool: :bonfire_common,
      ssl_options:
        default_http_ssl_options(opts[:ssl_options] || [], adapter_options[:ssl_options] || [])
    ]

    final_options =
      base_options
      |> Keyword.merge(to_options(adapter_options))
      |> Keyword.merge(opts)
      |> Keyword.merge(if proxy_url, do: [proxy: to_options(proxy_url)], else: [])

    {Tesla.Adapter.Hackney, final_options}
  end

  def adapter_options({adapter, base_opts}, opts), do: {adapter, Keyword.merge(base_opts, opts)}
  def adapter_options(_, opts), do: opts

  @doc """
  Returns default SSL options for low-level networking functions.

  You can override any option by passing a keyword list.

  ## Examples

      iex> Bonfire.Common.HTTP.Connection.default_ssl_options()
      [
        verify: :verify_peer,
        cacertfile: :certifi.cacertfile()
      ]

      iex> Bonfire.Common.HTTP.Connection.default_ssl_options(verify: :verify_none)
      [
        verify: :verify_none,
        cacertfile: :certifi.cacertfile()
      ]
  """
  def default_ssl_options(overrides \\ [], ssl_config \\ nil) do
    ssl_config = ssl_config || Config.get([:http, :adapter_options, :ssl_options]) || []

    [
      verify: :verify_peer,
      cacertfile: :certifi.cacertfile()
      # insecure: false,
      # versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"],
    ]
    |> Keyword.merge(ssl_config)
    |> Keyword.merge(overrides)
  end

  @doc """
  Returns default SSL options for low-level networking functions.

  You can override any option by passing a keyword list.

  ## Examples

      iex> Bonfire.Common.HTTP.Connection.default_ssl_options()
      [
        verify: :verify_peer,
        cacertfile: :certifi.cacertfile(),
        verify_fun: &:ssl_verify_hostname.verify_fun/3
      ]

      iex> Bonfire.Common.HTTP.Connection.default_ssl_options(verify: :verify_none)
      [
        verify: :verify_none,
        cacertfile: :certifi.cacertfile(),
        verify_fun: &:ssl_verify_hostname.verify_fun/3
      ]
  """
  def default_http_ssl_options(overrides \\ [], ssl_config \\ nil) do
    default_ssl_options(overrides, ssl_config)
    |> Keyword.put_new(:verify_fun, &:ssl_verify_hostname.verify_fun/3)
  end
end
