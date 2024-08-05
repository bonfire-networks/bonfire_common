defmodule Bonfire.Common.URIs do
  @moduledoc "URI/URL/path helpers"
  import Untangle
  use Arrows
  import Bonfire.Common.Extend
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Cache
  alias Bonfire.Me.Characters
  alias Bonfire.Common
  alias Common.Types

  @doc """
  Validates a URI string.

  ## Examples

      iex> {:ok, %URI{scheme: "http", host: "example.com"}} = validate_uri("http://example.com")

      iex> {:error, %URI{scheme: nil, host: nil}} = validate_uri("invalid_uri")

  """
  def validate_uri(str) do
    uri = URI.parse(str)

    case uri do
      %URI{scheme: nil} -> {:error, uri}
      %URI{host: nil} -> {:error, uri}
      _ -> {:ok, uri}
    end
  end

  @doc """
  Returns true if the given string is a valid URI.

      iex> is_uri?("http://example.com")
      true

      iex> is_uri?("invalid_uri")
      false
  """
  def is_uri?(str) do
    case URI.parse(str) do
      %URI{scheme: nil} -> false
      %URI{host: nil} -> false
      _ -> true
    end
  end

  @doc """
  Returns the path (URL on the local instance) for the given object/struct (eg. a User), view or schema module, or path name (atom defined in routes), along with optional arguments.

  Returns the path (URL on the local instance) for the given object/struct (e.g., a User), view or schema module, or path name (atom defined in routes), along with optional arguments.

  ## Examples

      > path(:user, [1], [])
      "/users/1"

      > path(User, [1], [])
      "/users/1"

      > path(%{id: "1"}, :show, [])
      "/users/1/show"

      > path(%{id: "1"}, [some: :args], [])
      "/users/1/some_args"

      iex> path("12345", [some: :args], [])
      nil
  """
  def path(view_module_or_path_name_or_object, args \\ [], opts \\ [])

  def path(view_module_or_path_name_or_object, %{id: id} = args, opts)
      when not is_struct(args),
      do: path(view_module_or_path_name_or_object, [id], opts)

  # not sure what this one is for? ^

  def path(%{id: _id} = object, action, opts) when is_atom(action),
    do: path(Types.object_type(object), [path_id(object), action], opts)

  def path(view_module_or_path_name_or_object, args, opts)
      when is_atom(view_module_or_path_name_or_object) and
             not is_nil(view_module_or_path_name_or_object) do
    ([Bonfire.Common.Config.endpoint_module(), view_module_or_path_name_or_object] ++
       List.wrap(args))
    |> debug("args")
    |> case Utils.maybe_apply(
              Bonfire.Web.Router.Reverse,
              :path,
              ...,
              fn error, details ->
                IO.inspect(error, label: "reverse_failed")

                if opts[:fallback] == false do
                  debug(details, inspect(error))
                else
                  voodoo_fallback(error, details)
                end
              end
            ) do
      "/%40" <> username ->
        "/@" <> username

      "/%2B" <> username ->
        "/+" <> username

      path when is_binary(path) ->
        path

      other ->
        warn(other, "Router didn't return a valid path")
        if opts[:fallback] != false, do: fallback(args)
    end
  rescue
    error in FunctionClauseError ->
      warn(
        error,
        "path: could not find a matching route for #{inspect(view_module_or_path_name_or_object)}"
      )

      debug(args, "path args used")

      nil

    error in ArgumentError ->
      warn(
        error,
        "path: could not find a matching route for #{inspect(view_module_or_path_name_or_object)}"
      )

      nil
  end

  # def path(%{replied: %{reply_to: %{id: _} = reply_to}} = object, args, opts) do
  #   reply_path(object, path(reply_to))
  # end
  # def path(%{replied: %{thread_id: thread_id}} = object, args, opts) when is_binary(thread_id) do
  #   reply_path(object, path(thread_id))
  # end
  # def path(%{reply_to: %{id: _} = reply_to} = object, args, opts) do
  #   reply_path(object, path(reply_to))
  # end
  # def path(%{thread_id: thread_id} = object, args, opts) when is_binary(thread_id) do
  #   reply_path(object, path(thread_id))
  # end

  def path(%{pointer_id: id} = object, args, opts), do: path_by_id(id, args, object, opts)

  def path(%{id: _id} = object, args, opts) do
    args_with_id =
      ([path_id(object)] ++ args)
      |> Enums.filter_empty([])
      |> debug("args_with_id")

    case Bonfire.Common.Types.object_type(object) do
      type when is_atom(type) and not is_nil(type) ->
        debug(type, "detected object_type for object")
        path(type, args_with_id, opts)

      none ->
        debug(none, "path_maybe_lookup_pointer")
        path_maybe_lookup_pointer(object, args, opts)
    end

    # rescue
    #   error in FunctionClauseError ->
    #     warn("path: could not find a matching route: #{inspect error} for object #{inspect object}")
    #     case object do
    #       %{character: %{username: username}} -> path(Bonfire.Data.Identity.User, [username] ++ args)
    #       %{username: username} -> path(Bonfire.Data.Identity.User, [username] ++ args)
    #       %{id: id} -> if opts[:fallback] !=false, do: fallback(id, args)
    #       _ -> if opts[:fallback] !=false, do: fallback(object, args)
    #     end
  end

  def path(id, args, opts) when is_binary(id), do: path_by_id(id, args, nil, opts)

  def path(other, _, _opts) do
    error(other, "path: could not find any matching route")
    # "#unrecognised-#{inspect(other)}"
    nil
  end

  defp path_maybe_lookup_pointer(%Needle.Pointer{id: id} = object, args, opts) do
    warn(object, "path: could not figure out the type of this pointer")

    if opts[:fallback] != false, do: fallback(id, args)
  end

  defp path_maybe_lookup_pointer(%{id: id} = object, args, opts) do
    debug(
      "path: could not figure out the type of this object, gonna try checking the pointer table"
    )

    path_by_id(id, args, object, opts)
  end

  def path_by_id(id, args, object, opts) when is_binary(id) do
    if Types.is_ulid?(id) do
      with {:ok, pointer} <-
             Cache.maybe_apply_cached(&Bonfire.Common.Needles.one/2, [
               id,
               [skip_boundary_check: true, preload: :character]
             ]) do
        debug(pointer, "path_by_id: found a pointer")

        (object || %{})
        |> Map.merge(pointer)
        |> path(args, opts)
      else
        _ ->
          warn("path_by_id: could not find a Pointer with id #{id}")
          if opts[:fallback] != false, do: fallback(id, args)
      end
    else
      warn("path_by_id: could not find a matching route for #{id}, using fallback path")
      if opts[:fallback] != false, do: fallback(id, args)
    end
  end

  def fallback(id, type, args) do
    do_fallback(List.wrap(type) ++ List.wrap(id) ++ List.wrap(args), 1)
  end

  def fallback(id, args) do
    fallback(List.wrap(id) ++ List.wrap(args))
  end

  def fallback(nil) do
    nil
  end

  def fallback([]) do
    nil
  end

  def fallback([nil]) do
    nil
  end

  def fallback(args) do
    List.wrap(args)
    |> do_fallback(0)
  end

  defp do_fallback(args, id_at \\ 0) do
    # debug(args, id_at)
    debug(args, "path_fallback")

    # TODO: configurable
    fallback_route = Needle.Pointer
    fallback_character_route = Bonfire.Data.Identity.Character

    case path_id(Enum.at(args, id_at) |> debug()) |> debug() do
      maybe_username_or_id
      when is_binary(maybe_username_or_id) and not is_nil(maybe_username_or_id) ->
        if Types.is_ulid?(maybe_username_or_id) do
          path(fallback_route, args, fallback: false)
        else
          path(fallback_character_route, args, fallback: false)
        end

      _ ->
        path(fallback_route, args, fallback: false)
    end
  end

  # defp reply_path(object, reply_to_path) when is_binary(reply_to_path) do
  #   reply_to_path <> "#" <> (Types.ulid(object) || "")
  # end

  # defp reply_path(object, _) do
  #   path(object)
  # end

  defp voodoo_fallback(_error, [_endpoint, type_module, args]) do
    fallback([], type_module, args)
  end

  defp voodoo_fallback(_error, [_endpoint, args]) do
    fallback(args)
  end

  # defp path_id("@"<>username), do: username
  defp path_id(%{username: username}) when is_binary(username), do: username

  defp path_id(%{display_username: "@" <> display_username}),
    do: display_username

  defp path_id(%{display_username: display_username}) when is_binary(display_username),
    do: display_username

  defp path_id(%{__struct__: schema, name: tag}) when schema == Bonfire.Tag.Hashtag,
    do: tag

  defp path_id(%{character: %{username: username}}) when is_binary(username), do: username

  defp path_id(%{__struct__: schema, character: _character} = obj)
       when schema != Needle.Pointer,
       do:
         obj
         # |> debug("with character")
         |> repo().maybe_preload(:character)
         |> Utils.e(:character, obj.id)
         |> path_id()

  defp path_id(%{id: id}), do: id
  defp path_id(other), do: other

  @doc """
  Returns the full URL (including domain and path) for a given object, module, or path name.

      iex> url_path(:user, [1])
      "http://localhost:4000/discussion/user/1"

  """
  def url_path(view_module_or_path_name_or_object, args \\ []) do
    base_url() <> path(view_module_or_path_name_or_object, args)
  end

  @doc """
  Returns the canonical URL (i.e., the one used for ActivityPub federation) of an object.

  ## Examples

      iex> canonical_url(%{canonical_uri: "http://example.com"})
      "http://example.com"

      iex> canonical_url(%{canonical_url: "http://example.com"})
      "http://example.com"

      iex> canonical_url(%{"canonicalUrl" => "http://example.com"})
      "http://example.com"

      iex> canonical_url(%{peered: %{canonical_uri: "http://example.com"}})
      "http://example.com"

      iex> canonical_url(%{character: %{canonical_uri: "http://example.com"}})
      "http://example.com"

      iex> canonical_url(%{character: %{peered: %{canonical_uri: "http://example.com"}}})
      "http://example.com"

      iex> canonical_url(%{peered: %Ecto.Association.NotLoaded{}})
      nil

      iex> canonical_url(%{created: %Ecto.Association.NotLoaded{}})
      nil

      iex> canonical_url(%{character: %Ecto.Association.NotLoaded{}})
      nil

      iex> canonical_url(%{character: %{peered: %{}}})
      nil

      iex> canonical_url(%{path: "http://example.com"})
      "http://example.com"

      iex> canonical_url(%{other: "data"})
      nil

  """
  def canonical_url(%{canonical_uri: canonical_url})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{canonical_url: canonical_url})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{"canonicalUrl" => canonical_url})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{peered: %{canonical_uri: canonical_url}})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{character: %{canonical_uri: canonical_url}})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{character: %{peered: %{canonical_uri: canonical_url}}})
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{peered: %Ecto.Association.NotLoaded{}} = object) do
    object = repo().maybe_preload(object, :peered)

    Utils.e(object, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object)
  end

  def canonical_url(%{peered: %{}} = object) do
    maybe_generate_canonical_url(object)
  end

  def canonical_url(%{created: %Ecto.Association.NotLoaded{}} = object) do
    object = repo().maybe_preload(object, created: [:peered])

    Utils.e(object, :created, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object)
  end

  def canonical_url(%{character: %Ecto.Association.NotLoaded{}} = object) do
    object = repo().maybe_preload(object, character: [:peered])

    Utils.e(object, :character, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object)
  end

  def canonical_url(%{character: %{peered: %{}}} = object) do
    maybe_generate_canonical_url(object)
  end

  def canonical_url(%{path: "http" <> _ = path} = object) do
    path
  end

  def canonical_url(object) do
    query_or_generate_canonical_url(object)
  end

  defp query_or_generate_canonical_url(object) do
    remote_canonical_url(object) ||
      maybe_generate_canonical_url(object)
  end

  def remote_canonical_url(object) do
    if module = maybe_module(Bonfire.Federate.ActivityPub.Peered) do
      # debug(object, "attempt to query Peered")
      module.get_canonical_uri(object)
      # |> debug("peered url")
    end
  end

  def maybe_generate_canonical_url(%{character: %{username: id}}) when is_binary(id) do
    maybe_generate_canonical_url(id)
  end

  def maybe_generate_canonical_url(%{username: id} = thing) when is_binary(id) do
    maybe_generate_canonical_url(id)
  end

  def maybe_generate_canonical_url(%{id: id} = thing) when is_binary(id) do
    maybe_generate_canonical_url(id)
  end

  def maybe_generate_canonical_url(id) when is_binary(id) do
    ap_base_path = Bonfire.Common.Config.get(:ap_base_path, "/pub")

    if Types.is_ulid?(id) or Types.is_uuid?(id) do
      "#{base_url()}#{ap_base_path}/objects/#{id}"
    else
      "#{base_url()}#{ap_base_path}/actors/#{id}"
    end
  end

  def maybe_generate_canonical_url(%{"id" => id}),
    do: maybe_generate_canonical_url(id)

  def maybe_generate_canonical_url(%{"username" => id}),
    do: maybe_generate_canonical_url(id)

  def maybe_generate_canonical_url(%{username: id}),
    do: maybe_generate_canonical_url(id)

  def maybe_generate_canonical_url(%{"displayUsername" => id}),
    do: maybe_generate_canonical_url(id)

  def maybe_generate_canonical_url(%{"preferredUsername" => id}),
    do: maybe_generate_canonical_url(id)

  def maybe_generate_canonical_url(_) do
    nil
  end

  @doc """
  Returns the homepage URI (as struct) of the local instance.

      iex> %URI{scheme: "http", host: "localhost"} = base_uri(:my_endpoint)

  """
  def base_uri(conn_or_socket \\ nil)

  def base_uri(%{endpoint: endpoint} = _socket), do: base_uri(endpoint)

  def base_uri(endpoint) when not is_nil(endpoint) and is_atom(endpoint) do
    if module_enabled?(endpoint) do
      endpoint.struct_url()
      # |> debug(endpoint)
    else
      base_uri_fallback(
        "endpoint module not available",
        endpoint,
        endpoint,
        Common.Config.endpoint_module()
      )
    end
  rescue
    e ->
      base_uri_fallback(
        "could not get struct_url from endpoint",
        e,
        endpoint,
        Common.Config.endpoint_module()
      )
  end

  def base_uri(_) do
    case Common.Config.endpoint_module() do
      endpoint when is_atom(endpoint) ->
        if module_enabled?(endpoint) do
          base_uri(endpoint)
        else
          error("endpoint module #{endpoint} not available")
        end

      _ ->
        error("requires a conn or :endpoint_module in Config")
    end
  end

  defp base_uri_fallback(msg, e, endpoint, main_endpoint_module) do
    if endpoint != main_endpoint_module do
      base_uri(main_endpoint_module)
    else
      error(e, msg)

      %URI{
        scheme: "https",
        host: Common.Config.get(:host) || System.get_env("HOSTNAME", "localhost")
      }
    end
  end

  @doc "Return the homepage URL (as string) of the local instance"
  def base_url(conn_or_socket_or_uri \\ nil)

  def base_url(%{host: host, port: 80}) when is_binary(host),
    do: "http://" <> host

  def base_url(%{host: host, port: 443}) when is_binary(host),
    do: "https://" <> host

  def base_url(%{scheme: scheme, host: host, port: port})
      when is_binary(host) and not is_nil(scheme) and not is_nil(port),
      do: "#{scheme}://#{host}:#{port}"

  def base_url(%{scheme: scheme, host: host}) when is_binary(host) and not is_nil(scheme),
    do: "#{scheme}://#{host}"

  def base_url(%{host: host, port: port}) when is_binary(host) and not is_nil(port),
    do: "http://#{host}:#{port}"

  def base_url(%{host: host}) when is_binary(host), do: "http://#{host}"

  def base_url(%URI{} = uri), do: error(uri, "instance has no valid host")

  def base_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> base_url()
  end

  def base_url(other) do
    with %URI{} = uri <- base_uri(other) do
      base_url(uri)
    else
      e ->
        error(e)
        ""
    end
  end

  @doc """
  Returns the base domain from the given URI or endpoint.

      iex> base_domain(%URI{host: "example.com", port: 443})
      "example.com"

  """
  def base_domain(uri_or_endpoint_or_conn \\ nil)

  def base_domain(%URI{} = uri) do
    case uri do
      %{host: host, port: port} when port not in [80, 443] ->
        "#{host}:#{port}"

      %{host: host} when is_binary(host) ->
        host

      other ->
        error(other, "instance has no valid host")
        ""
    end
  end

  def base_domain(url) when is_binary(url) do
    url
    |> URI.parse()
    |> base_domain()
  end

  def base_domain(endpoint_or_conn) do
    with %URI{} = uri <- base_uri(endpoint_or_conn) do
      base_domain(uri)
    end
  end

  @doc """
  Removes the scheme from a URL to get the display URL.

      iex> display_url("https://example.com/path")
      "example.com/path"

      iex> display_url("http://example.com/path")
      "example.com/path"

      iex> display_url("/path")
      "/path"

  """
  def based_url(url, conn \\ nil)
  def based_url("http" <> _ = url, _conn), do: url
  def based_url("/" <> url, conn), do: "#{base_url(conn)}/#{url}"
  def based_url(url, _), do: url

  def display_url("https://" <> url), do: url
  def display_url("http://" <> url), do: url
  def display_url(url), do: url

  @doc """
  Generates a static path based on the given path and endpoint module.

      iex> static_path("/assets/image.png")
      "/assets/image.png"
  """
  def static_path(path, endpoint_module \\ Bonfire.Common.Config.endpoint_module()) do
    endpoint_module.static_path(path)
  end
end
