defmodule Bonfire.Common.HTTP do
  @moduledoc """
  Module for building and performing HTTP requests.
  """
  import Untangle
  alias Bonfire.Common.HTTP.Connection
  alias Bonfire.Common.HTTP.RequestBuilder
  alias Bonfire.Common.Cache

  @type t :: __MODULE__

  @doc """
  Builds and perform http request.

  # Arguments:
  `method` - :get, :post, :put, :delete
  `url`
  `body`
  `headers` - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
  `options` - custom, per-request middleware or adapter options

  # Returns:
  `{:ok, %Tesla.Env{}}` or `{:error, error}`

  """
  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    try do
      options =
        process_request_options(options)
        |> process_sni_options(url)

      # |> info("options")

      params = Keyword.get(options, :params, [])

      %{}
      |> RequestBuilder.method(method)
      |> RequestBuilder.headers(headers)
      |> RequestBuilder.opts(options)
      |> RequestBuilder.url(url)
      |> RequestBuilder.add_param(:body, :body, body)
      |> RequestBuilder.add_param(:query, :query, params)
      |> Enum.into([])
      |> (&Tesla.request(Connection.new(options), &1)).()
    rescue
      e in Tesla.Mock.Error ->
        error(e, "Test mock HTTP error")

      e ->
        error(e, "HTTP request failed")
    catch
      :exit, e ->
        error(e, "HTTP request exited")
    end
  end

  defp process_request_options(options) do
    {_adapter, opts} = Connection.adapter_options([])
    Keyword.merge(opts, options)
  end

  defp process_sni_options(options, nil), do: options

  defp process_sni_options(options, url) do
    uri = URI.parse(url)
    host = to_charlist(uri.host)

    case uri.scheme do
      "https" -> options ++ [ssl: [server_name_indication: host]]
      _ -> options
    end
  end

  @doc """
  Makes a GET request

  see `request/5`
  """
  def get(url, headers \\ [], options \\ []),
    do: request(:get, url, "", headers, options)

  def get_cached(url) do
    Cache.maybe_apply_cached(&get/1, [url])
  end

  @doc """
  Makes a POST request

  see `request/5`
  """
  def post(url, body, headers \\ [], options \\ []),
    do: request(:post, url, body, headers, options)

  @doc """
  Makes a PUT request

  see `request/5`
  """
  def put(url, body, headers \\ [], options \\ []),
    do: request(:put, url, body, headers, options)

  @doc """
  Makes a PATCH request

  see `request/5`
  """
  def patch(url, body, headers \\ [], options \\ []),
    do: request(:patch, url, body, headers, options)

  @doc """
  Makes a DELETE request

  see `request/5`
  """
  def delete(url, body \\ "", headers \\ [], options \\ []),
    do: request(:delete, url, body, headers, options)

  @behaviour Neuron.Connection
  @impl Neuron.Connection
  def call(body, options) do
    raise "TODO"
  end
end
