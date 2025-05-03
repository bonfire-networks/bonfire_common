defmodule Bonfire.Common.HTTP.Connection do
  @moduledoc """
  Specifies connection options for HTTP requests
  """
  use Bonfire.Common.Config

  def new(opts \\ []) do
    adapter = Application.get_env(:tesla, :adapter) || {Tesla.Adapter.Finch, name: Bonfire.Finch}
    Tesla.client([], adapter_options(adapter, Keyword.get(opts, :adapter, [])))
  end

  def adapter_options(adapter \\ Tesla.Adapter.Hackney, opts)

  def adapter_options(Tesla.Adapter.Hackney, opts) do
    adapter_options = Config.get([:http, :adapter_options])
    proxy_url = Config.get([:http, :proxy_url])

    {Tesla.Adapter.Hackney,
     [
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
     |> Keyword.merge(adapter_options)
     |> Keyword.merge(opts)
     |> Keyword.merge(proxy: proxy_url)}
  end

  def adapter_options({adapter, base_opts}, opts), do: {adapter, Keyword.merge(base_opts, opts)}
  def adapter_options(_, opts), do: opts
end
