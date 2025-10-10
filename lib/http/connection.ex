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
    adapter_options = Config.get([:http, :adapter_options]) || []
    proxy_url = Config.get([:http, :proxy_url])

    base_options = [
      connect_timeout: 10_000,
      recv_timeout: 20_000,
      follow_redirect: true,
      pool: :bonfire_common,
      ssl_options: [
        # insecure: true
        #  versions: [:'tlsv1.2'],
        verify: :verify_peer,
        cacertfile: :certifi.cacertfile(),
        verify_fun: &:ssl_verify_hostname.verify_fun/3
        # customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)] 
      ]
    ]

    final_options =
      base_options
      |> Keyword.merge(to_options(adapter_options))
      |> Keyword.merge(to_options(opts))
      |> Keyword.merge(if proxy_url, do: [proxy: to_options(proxy_url)], else: [])

    {Tesla.Adapter.Hackney, final_options}
  end

  def adapter_options({adapter, base_opts}, opts), do: {adapter, Keyword.merge(base_opts, opts)}
  def adapter_options(_, opts), do: opts
end
