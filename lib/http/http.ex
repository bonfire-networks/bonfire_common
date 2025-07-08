defmodule Bonfire.Common.HTTP do
  @moduledoc """
  Module for building and performing HTTP requests.
  """
  import Untangle
  import Bonfire.Common.Opts
  alias Bonfire.Common.HTTP.Connection
  alias Bonfire.Common.HTTP.RequestBuilder
  alias Bonfire.Common.Cache

  # 1 hours
  @hms 1_000 * 60 * 60

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
      processed_options =
        try do
          process_request_options(options)
        rescue
          e ->
            error(e, "Error in process_request_options call")
            to_options(options)
        end

      final_options = process_sni_options(processed_options, url)

      # Remove url and headers from final_options since they're handled separately
      adapter_options =
        final_options
        |> Keyword.drop([:url, :headers])

      params = Keyword.get(adapter_options, :params, [])

      %{}
      |> RequestBuilder.method(method)
      |> RequestBuilder.headers(headers)
      |> RequestBuilder.opts(adapter_options)
      |> RequestBuilder.url(url)
      |> RequestBuilder.add_param(:body, :body, body)
      |> RequestBuilder.add_param(:query, :query, params)
      |> Enum.into([])
      |> (&Tesla.request(Connection.new(adapter_options), &1)).()
    rescue
      e in Tesla.Mock.Error ->
        error(e, "Test mock HTTP error")

        # e ->
        #   error(e, "HTTP request failed")
    catch
      :exit, e ->
        error(e, "HTTP request exited")
    end
  end

  defp process_request_options(options) do
    try do
      {_adapter, opts} = Connection.adapter_options([])

      # opts is already a keyword list from Connection.adapter_options
      # options should be converted to a keyword list
      options_kw = to_options(options)

      # Now we can safely merge two keyword lists
      Keyword.merge(opts, options_kw)
    rescue
      e ->
        error(e, "Error in process_request_options")
        # Return a safe default
        to_options(options)
    end
  end

  defp process_sni_options(options, nil), do: options

  defp process_sni_options(options, url) do
    uri = URI.parse(url)
    host = to_charlist(uri.host)

    case uri.scheme do
      "https" ->
        # Ensure options is a keyword list before concatenating
        options = to_options(options)
        options ++ [ssl: [server_name_indication: host]]

      _ ->
        options
    end
  end

  @doc """
  Makes a GET request

  see `request/5`
  """
  def get(url, headers \\ [], options \\ []),
    do: request(:get, url, "", headers, options)

  def get_body(url, headers \\ [], options \\ []) do
    with {:ok, %{body: body}} when is_binary(body) <-
           get(url, headers, options) do
      body
    else
      e ->
        warn(e, "Could not fetch remote content for #{url}")
        nil
    end
  end

  def get_cached(url, opts \\ []) do
    Cache.maybe_apply_cached(
      &get/1,
      [url],
      opts
      |> Keyword.put_new_lazy(:cache_key, fn ->
        "fetched:#{url}"
      end)
      |> Keyword.put_new_lazy(:expire, fn ->
        # 12 hours by default
        @hms * (opts[:expire_hr] || 12)
      end)
    )
  end

  def get_cached_body(url, opts \\ []) do
    Cache.maybe_apply_cached(
      &get_body/1,
      [url],
      opts
      |> Keyword.put_new_lazy(:cache_key, fn ->
        "fetched_body:#{url}"
      end)
      |> Keyword.put_new_lazy(:expire, fn ->
        # 12 hours by default
        @hms * (opts[:expire_hr] || 12)
      end)
    )
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

  def ensure_ready do
    case Application.ensure_all_started(:finch) do
      {:ok, _} ->
        debug("Finch started successfully")
        # Also start the specific Finch pool if needed
        case Finch.start_link(name: Bonfire.Finch, pools: %{:default => [size: 10]}) do
          {:ok, _} -> debug("Bonfire.Finch pool started")
          {:error, {:already_started, _}} -> debug("Bonfire.Finch pool already started")
          {:error, reason} -> debug(reason, "Failed to start Bonfire.Finch pool")
        end

      {:error, reason} ->
        debug(reason, "Failed to start Finch")
    end
  end

  @behaviour Neuron.Connection
  @impl Neuron.Connection
  def call(body, options) do
    # Ensure options is a keyword list
    options = to_options(options)

    method = Keyword.get(options, :method, :post)
    url = Keyword.get(options, :url, "")
    headers = Keyword.get(options, :headers, [])

    case request(method, url, body, headers, options) do
      {:ok, %Tesla.Env{status: status, body: response_body, headers: response_headers}} ->
        {:ok, %{status: status, body: response_body, headers: response_headers}}

      {:error, error} ->
        {:error, error}
    end
  end
end
