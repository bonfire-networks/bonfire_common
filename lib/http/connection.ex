defmodule Bonfire.Common.HTTP.Connection do
  @moduledoc """
  Specifies connection options for HTTP requests
  """
  alias Bonfire.Common.Config

  @default_hackney_options [
    connect_timeout: 10_000,
    recv_timeout: 20_000,
    follow_redirect: true,
    pool: :bonfire_common
  ]

  def new(opts \\ []) do
    adapter = Application.get_env(:tesla, :adapter)
    Tesla.client([], {adapter, hackney_options(opts)})
  end

  def hackney_options(opts) do
    passed_options = Keyword.get(opts, :adapter, [])
    adapter_options = Config.get([:http, :adapter_options])
    proxy_url = Config.get([:http, :proxy_url])

    @default_hackney_options
    |> Keyword.merge(adapter_options)
    |> Keyword.merge(proxy: proxy_url)
    |> Keyword.merge(passed_options)
    # |> IO.inspect()
  end
end
