defmodule Bonfire.Common.URIs do

  alias Bonfire.Common.Utils
  alias Bonfire.Me.Characters
  alias Plug.Conn.Query
  import Where

  def path(view_module_or_path_name_or_object, args \\ [])

  def path(view_module_or_path_name_or_object, %{id: id} = args) when not is_struct(args), do: path(view_module_or_path_name_or_object, [id])

  def path(view_module_or_path_name_or_object, args) when not is_list(args), do: path(view_module_or_path_name_or_object, [args])

  def path(view_module_or_path_name_or_object, args) when is_atom(view_module_or_path_name_or_object) and not is_nil(view_module_or_path_name_or_object) do
    apply(Bonfire.Web.Router.Reverse, :path, [Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint), view_module_or_path_name_or_object] ++ args)
  end

  def path(%{pointer_id: id} = object, args), do: path_by_id(id, args)
  def path(%{id: id} = object, args) do
    args_with_id = ([path_id(object)] ++ args) |> Utils.filter_empty([]) #|> IO.inspect()

    case Bonfire.Common.Types.object_type(object) do
      type when is_atom(type) and not is_nil(type) ->
        debug("path: detected object_type #{inspect type}")
        path(type, args_with_id)

      none ->
        path_maybe_lookup_pointer(object, args)
    end

  rescue
    error in FunctionClauseError ->
      warn("path: could not find a matching route: #{inspect error} for object #{inspect object}")
      case object do
        %{character: %{username: username}} -> path(Bonfire.Data.Identity.User, [username] ++ args)
        %{username: username} -> path(Bonfire.Data.Identity.User, [username] ++ args)
        %{id: id} -> fallback(id, args)
        _ -> fallback(object, args)
      end
  end

  def path(id, args) when is_binary(id), do: path_by_id(id, args)

  def path(other, _) do
    error("path: could not find any matching route for #{inspect other}")
    "#unrecognised-#{inspect other}"
  end

  defp path_maybe_lookup_pointer(%Pointers.Pointer{id: id} = object, args) do
    error("path: could not figure out the type of this pointer: #{inspect object}")
    fallback(id, args)
  end

  defp path_maybe_lookup_pointer(%{id: id} = object, args) do
    debug("path: could not figure out the type of this object, gonna try checking the pointer table")
    path_by_id(id, args, object)
  end

  def fallback(id, args) do
    path(Bonfire.Social.Web.DiscussionLive, [id] ++ args)
  end

  def path_by_id(id, args, object \\ %{}) when is_binary(id) do
    if Utils.is_ulid?(id) do
      with {:ok, pointer} <- Bonfire.Common.Pointers.one(id, skip_boundary_check: true) do
        debug("path_by_id: found a pointer #{inspect pointer}")
        object
        |> Map.merge(pointer)
        |> path(args)
      else _ ->
        error("path_by_id: could not find a Pointer with id #{id}")
        fallback(id, args)
      end
    else
      case path_id(id) do
        maybe_username when is_binary(maybe_username) and not is_nil(maybe_username) ->
          debug("path_by_id: possibly found a username #{inspect maybe_username}")
          path(Bonfire.Data.Identity.User, maybe_username)

        _ ->
          error("path_by_id: could not find a matching route for #{id}")
          fallback(id, args)
      end

    end
  end


  # defp path_id("@"<>username), do: username
  defp path_id(%{username: username}), do: username
  defp path_id(%{display_username: display_username}), do: path_id(display_username)
  defp path_id(%{character: character} = obj), do: obj |> Bonfire.Repo.maybe_preload(:character) |> Utils.e(:character, nil) |> path_id()
  defp path_id(%{id: id}), do: id
  defp path_id(other), do: other

  def url(view_module_or_path_name_or_object, args \\ []) do
    base_url()<>path(view_module_or_path_name_or_object, args)
  end

  def canonical_url(%{canonical_uri: canonical_url}) when is_binary(canonical_url) do
    canonical_url
  end
  def canonical_url(%{canonical_url: canonical_url}) when not is_nil(canonical_url) do
    canonical_url
  end
  def canonical_url(%{"canonicalUrl"=> canonical_url}) when is_binary(canonical_url) do
    canonical_url
  end
  def canonical_url(%{peered: %{canonical_uri: canonical_url}}) when is_binary(canonical_url) do
    canonical_url
  end
  def canonical_url(%{peered: _not_loaded} = object) do
    Bonfire.Repo.maybe_preload(object, :peered)
    |> Utils.e(:peered, :canonical_uri, nil)
        ||
       maybe_generate_canonical_url(object)
  end
  def canonical_url(%{created: _not_loaded} = object) do
    Bonfire.Repo.maybe_preload(object, [created: [:peered]])
    |> Utils.e(:created, :peered, :canonical_uri, nil)
        ||
       maybe_generate_canonical_url(object)
  end
  def canonical_url(%{character: _not_loaded} = object) do
    Bonfire.Repo.maybe_preload(object, [character: [:peered]])
    |> Utils.e(:character, :peered, :canonical_uri, nil)
        ||
       maybe_generate_canonical_url(object)
  end
  def canonical_url(object) do
    if Utils.module_enabled?(Bonfire.Federate.ActivityPub.Peered) do
      Bonfire.Federate.ActivityPub.Peered.get_canonical_uri(object) || maybe_generate_canonical_url(object)
    else
      maybe_generate_canonical_url(object)
    end
  end

  defp maybe_generate_canonical_url(%{id: id} = thing) when is_binary(id) do
    if Utils.module_enabled?(Characters) do
      # check if object is a Character (in which case use actor URL)
      case Characters.character_url(thing) do
        nil -> maybe_generate_canonical_url(id)
        character_url -> character_url
      end
    else
      maybe_generate_canonical_url(id)
    end
  end

  defp maybe_generate_canonical_url(id) when is_binary(id) do
    ap_base_path = Bonfire.Common.Config.get(:ap_base_path, "/pub")
    prefix = if Utils.is_ulid?(id), do: "/objects/", else: "/actors/"
    base_url() <> ap_base_path <> prefix <> id
  end

  defp maybe_generate_canonical_url(%{"id" => id}), do: maybe_generate_canonical_url(id)
  defp maybe_generate_canonical_url(%{"username" => id}), do: maybe_generate_canonical_url(id)
  defp maybe_generate_canonical_url(%{username: id}), do: maybe_generate_canonical_url(id)
  defp maybe_generate_canonical_url(%{"displayUsername" => id}), do: maybe_generate_canonical_url(id)
  defp maybe_generate_canonical_url(%{"preferredUsername" => id}), do: maybe_generate_canonical_url(id)

  defp maybe_generate_canonical_url(_) do
    nil
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
      error("endpoint module not found: #{inspect endpoint}")
      ""
    end
  rescue e ->
    error("could not get struct_url from endpoint: #{inspect e}")
    ""
  end
  def base_url(_) do
    case Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint) do
      endpoint when is_atom(endpoint) ->
        if Utils.module_enabled?(endpoint) do
          base_url(endpoint)
        else
          error("endpoint module #{endpoint} not available")
          ""
        end
      _ ->
        error("requires a conn or endpoint module")
        ""
    end
  end

  def instance_domain(endpoint_or_conn \\ nil) do
    case base_url(endpoint_or_conn) |> URI.parse do
      %{host: host} -> host
      other ->
        error(other, "base_url returned no host")
        ""
    end
  end


  # copies the 'go' part of the query string, if any
  def copy_go(%{go: go}), do: "?" <> Query.encode(go: go)
  def copy_go(%{"go" => go}), do: "?" <> Query.encode(go: go)
  def copy_go(_), do: ""

  # TODO: should we preserve query strings?
  def go_query(url) when is_binary(url), do: "?" <> Query.encode(go: url)
  def go_query(conn), do: "?" <> Query.encode(go: conn.request_path)

  # TODO: we should validate this a bit harder. Phoenix will prevent
  # us from sending the user to an external URL, but it'll do so by
  # means of a 500 error.
  def valid_go_path?("/" <> _), do: true
  def valid_go_path?(_), do: false

  def go_where?(_conn, %Ecto.Changeset{}=cs, default) do
    go_where?(_conn, cs.changes, default)
  end

  def go_where?(_conn, params, default) do
    go = Utils.e(params |> dump, :go, default) |> dump
    if valid_go_path?(go), do: go, else: default
  end
end
