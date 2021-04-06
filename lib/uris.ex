defmodule Bonfire.Common.URIs do

  alias Bonfire.Common.Utils
  alias Bonfire.Me.Characters

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
    if Utils.module_exists?(Characters) do
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
  def base_url(%{scheme: :http, host: host, port: 80}), do: "http://"<>host
  def base_url(%{scheme: :https, host: host, port: 443}), do: "https://"<>host
  def base_url(%{scheme: scheme, host: host, port: port}), do: "#{scheme}:#{port}//"<>host
  def base_url(_) do
    try do
      endpoint = Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint)
      if Code.ensure_loaded?(endpoint), do: endpoint.url(), else: "/"
    rescue _ ->
      "/"
    end
  end

end
