defmodule Bonfire.Common.URIs do

  alias Bonfire.Common.Utils
  alias Bonfire.Me.Characters
  alias Plug.Conn.Query
  require Logger

  def path(view_module_or_path_name, args \\ [])
  def path(view_module_or_path_name, args) when not is_list(args), do: path(view_module_or_path_name, [args])
  def path(view_module_or_path_name, args) do
    apply(Bonfire.Web.Router.Reverse, :path, [Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint), view_module_or_path_name] ++ args)
  end


  def canonical_url(%{canonical_url: canonical_url}) when not is_nil(canonical_url) do
    canonical_url
  end

  # def canonical_url(%{character: _character} = thing) do
  # Do we store the URL somewhere?
  #   repo().maybe_preload(thing, :character)
  #   canonical_url(Map.get(thing, :character))
  # end

  def canonical_url(object) do
      generate_canonical_url(object)
  end

  defp generate_canonical_url(%{id: id} = thing) when is_binary(id) do
    if Utils.module_enabled?(Characters) do
      # check if object is a Character (in which case use actor URL)
      case Characters.character_url(thing) do
        nil -> generate_canonical_url(id)
        character_url -> character_url
      end
    else
      generate_canonical_url(id)
    end
  end

  defp generate_canonical_url(id) when is_binary(id) do
    ap_base_path = Bonfire.Common.Config.get(:ap_base_path, "/pub")
    base_url() <> ap_base_path <> "/objects/" <> id
  end


  def base_url(conn \\ nil)
  def base_url(%{scheme: scheme, host: host, port: 80}) when scheme in [:http, "http"], do: "http://"<>host
  def base_url(%{scheme: scheme, host: host, port: 443}) when scheme in [:https, "https"], do: "https://"<>host
  def base_url(%{host: host, port: 443}), do: "https://"<>host
  def base_url(%{scheme: scheme, host: host, port: port}), do: "#{scheme}://#{host}:#{port}"
  def base_url(%{host: host}), do: "http://#{host}"
  def base_url(endpoint) when not is_nil(endpoint) and is_atom(endpoint) do
    if Code.ensure_loaded?(endpoint) do
      endpoint.struct_url() |> base_url()
    else
      Logger.info("base_url: endpoint module not found: #{inspect endpoint}")
      ""
    end
  rescue e ->
    Logger.info("base_url: #{inspect e}")
    ""
  end
  def base_url(_) do
    case Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint) do
      endpoint when is_atom(endpoint) -> base_url(endpoint)
      _ ->
        Logger.info("base_url: requires an endpoint module")
        ""
    end
  end


  # copies the 'go' part of the query string, if any
  def copy_go(%{go: go}), do: "?" <> Query.encode(go: go)
  def copy_go(%{"go" => go}), do: "?" <> Query.encode(go: go)
  def copy_go(_), do: ""

  # TODO: should we preserve query strings?
  def go_query(conn), do: "?" <> Query.encode(go: conn.request_path)

  # TODO: we should validate this a bit harder. Phoenix will prevent
  # us from sending the user to an external URL, but it'll do so by
  # means of a 500 error.
  def valid_go_path?("/" <> _), do: true
  def valid_go_path?(_), do: false

  def go_where?(_conn, %Ecto.Changeset{}, default) do
    default
  end

  def go_where?(_conn, params, default) do
    go = params[:go] || params["go"]
    if valid_go_path?(go), do: go, else: default
  end
end
