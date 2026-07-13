defmodule Bonfire.Common.URIs do
  @moduledoc "URI/URL/path helpers"
  import Untangle
  use Arrows
  use Bonfire.Common.E
  use Bonfire.Common.Config
  use Bonfire.Common.Localise
  import Bonfire.Common.Extend
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Cache
  alias Bonfire.Common
  alias Common.Types

  @doc """
  Validates a URI string and returns a tuple.

  ## Examples

      iex> {:ok, %URI{scheme: "http", host: "example.com"}} = validate_uri("http://example.com")

      iex> {:error, %URI{scheme: nil, host: nil}} = validate_uri("invalid_uri")

  """
  def validate_uri(str) do
    uri = URI.parse(str)

    case uri do
      %URI{scheme: nil, host: nil, path: path_as_host} when is_binary(path_as_host) ->
        # workaround for domain names provided with no scheme
        if String.contains?(path_as_host, ".") and not String.contains?(path_as_host, "@"),
          do: {:ok, %{uri | host: path_as_host, path: nil, scheme: "http"}},
          else: {:error, uri}

      %URI{scheme: nil} ->
        {:error, uri}

      %URI{host: nil} ->
        {:error, uri}

      _ ->
        {:ok, uri}
    end
  end

  @doc """
  Validates a URI string and returns a boolean.

  ## Examples

      iex> true == validate_uri("http://example.com")

      iex> false == validate_uri("invalid_uri")
  """
  def valid_url?(str) do
    uri = URI.parse(str)

    case uri do
      # workaround for domain names provided with no scheme
      %URI{scheme: nil, host: nil, path: path_as_host} when is_binary(path_as_host) ->
        String.contains?(path_as_host, ".") and not String.contains?(path_as_host, "@")

      %URI{scheme: nil} ->
        false

      %URI{host: nil} ->
        false

      _uri ->
        true
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

      > path("12345", [some: :args], [])
      nil
  """
  def path(view_module_or_path_name_or_object, args \\ [], opts \\ [])

  def path(view_module_or_path_name_or_object, %{id: id} = args, opts)
      when not is_struct(args),
      do: path(view_module_or_path_name_or_object, [id], opts)

  # not sure what this one is for? ^

  def path(%{id: _id} = object, action, opts) when is_atom(action),
    do: path(Types.object_type(object), [path_id(object, opts), action], opts)

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
              fallback_fun: fn error, details ->
                if opts[:fallback] == false do
                  debug(details, inspect(error))
                else
                  voodoo_fallback(error, details, opts)
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
        if opts[:fallback] != false, do: fallback(args, opts)
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
      ([path_id(object, opts)] ++ args)
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
    #       %{id: id} -> if opts[:fallback] !=false, do: fallback(id, args, opts)
    #       _ -> if opts[:fallback] !=false, do: fallback(object, args, opts)
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

    if opts[:fallback] != false, do: fallback(id, args, opts)
  end

  defp path_maybe_lookup_pointer(%{id: id} = object, args, opts) do
    debug(
      "path: could not figure out the type of this object, gonna try checking the pointer table"
    )

    path_by_id(id, args, object, opts)
  end

  def path_by_id(id, args, object, opts) when is_binary(id) do
    if Types.is_uid?(id) do
      with {:ok, pointer} <-
             Cache.maybe_apply_cached(
               &Bonfire.Common.Needles.one/2,
               [
                 id,
                 [skip_boundary_check: true, preload: :character]
               ],
               check_env: false
             ) do
        debug(pointer, "found a pointer")

        (object || %{})
        |> Map.merge(pointer)
        |> path(args, opts)
      else
        {:error, :not_found} ->
          error(id, "could not find a Pointer for ID")
          nil

        _ ->
          error(id, "unexpected error trying to find find a Pointer for ID")
          if opts[:fallback] != false, do: fallback(id, args, opts)
      end
    else
      warn("could not find a matching route for #{id}, using fallback path")
      if opts[:fallback] != false, do: fallback(id, args, opts)
    end
  end

  def fallback(id, type, args, opts) do
    do_fallback(List.wrap(type) ++ List.wrap(id) ++ List.wrap(args), 1, opts)
  end

  def fallback(id, args, opts) do
    fallback(List.wrap(id) ++ List.wrap(args), opts)
  end

  def fallback(nil, _) do
    nil
  end

  def fallback([], _) do
    nil
  end

  def fallback([nil], _) do
    nil
  end

  def fallback(args, opts) do
    List.wrap(args)
    |> do_fallback(0, opts)
  end

  defp do_fallback(args, id_at \\ 0, opts) do
    # debug(args, id_at)
    debug(args, "path_fallback")

    fallback_route =
      Config.get([:ui, :fallback_route_schemas, :default], Needle.Pointer,
        name: l("Default fallback route"),
        description: l("What route/view to use for data types that don't have one")
      )

    fallback_character_route =
      Config.get([:ui, :fallback_route_schemas, :default], Bonfire.Data.Identity.Character,
        name: l("Character fallback route"),
        description:
          l(
            "What route/view to use for character types that don't have one (eg. topics or groups with related UI enabled)"
          )
      )

    case path_id(Enum.at(args, id_at), opts) do
      maybe_username_or_id
      when is_binary(maybe_username_or_id) and not is_nil(maybe_username_or_id) ->
        if Types.is_uid?(maybe_username_or_id) do
          path(fallback_route, args, fallback: false)
        else
          path(fallback_character_route, args, fallback: false)
        end

      _ ->
        path(fallback_route, args, fallback: false)
    end
  end

  # defp reply_path(object, reply_to_path) when is_binary(reply_to_path) do
  #   reply_to_path <> "#" <> (Types.uid(object) || "")
  # end

  # defp reply_path(object, _) do
  #   path(object)
  # end

  defp voodoo_fallback(_error, [_endpoint, type_module, args], opts) do
    fallback([], type_module, args, opts)
  end

  defp voodoo_fallback(_error, [_endpoint, args], opts) do
    fallback(args, opts)
  end

  # defp path_id("@"<>username, _), do: username
  defp path_id(%{username: username}, _opts) when is_binary(username), do: username

  defp path_id(%{display_username: "@" <> display_username}, _opts),
    do: display_username

  defp path_id(%{display_username: display_username}, _opts) when is_binary(display_username),
    do: display_username

  defp path_id(%{character: %{username: username}}, _opts) when is_binary(username), do: username

  defp path_id(%{__struct__: schema, name: tag}, _opts) when schema == Bonfire.Tag.Hashtag,
    do: tag

  defp path_id(%{character: %{username: username}}, _opts) when is_binary(username), do: username

  defp path_id(%{__struct__: %{id: id} = schema, character: _character} = obj, opts)
       when schema != Needle.Pointer do
    if opts[:preload_if_needed] == false do
      # debug(obj, "obj without preload_if_needed")
      id
    else
      obj
      # TODO: what does this do and why?
      |> repo().maybe_preload(:character)
      |> e(:character, id)
      |> path_id(preload_if_needed: false)
    end
  end

  defp path_id(%{id: id}, _), do: id
  defp path_id(other, _), do: other

  @doc """
  Returns the full URL (including domain and path) for a given object, module, or path name.

      > url_path(:user, [1])
      "http://localhost:4000/discussion/user/1"

  """
  def url_path(view_module_or_path_name_or_object, args \\ []) do
    base_url() <> (path(view_module_or_path_name_or_object, args) || "")
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

      iex> canonical_url(%{peered: %Ecto.Association.NotLoaded{}}, preload_if_needed: true)
      nil

      iex> canonical_url(%{created: %Ecto.Association.NotLoaded{}}, preload_if_needed: true)
      nil

      iex> canonical_url(%{character: %Ecto.Association.NotLoaded{}}, preload_if_needed: true)
      nil

      iex> canonical_url(%{character: %{peered: %{}}})
      nil

      iex> canonical_url(%{path: "http://example.com"})
      "http://example.com"

      iex> canonical_url(%{other: "data"})
      nil

  """
  def canonical_url(object, opts \\ [])

  def canonical_url(%{canonical_uri: canonical_url}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{canonical_url: canonical_url}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{"canonicalUrl" => canonical_url}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{peered: %{canonical_uri: canonical_url}}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{character: %{canonical_uri: canonical_url}}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  def canonical_url(%{character: %{peered: %{canonical_uri: canonical_url}}}, _opts)
      when is_binary(canonical_url) do
    canonical_url
  end

  # Character-bearing structs (a User or Category) carry their locality on `character.peered`, not top-level `:peered`, so handle them before the top-level `:peered` clauses below (otherwise a local actor with an unloaded top-level `:peered` would wrongly trip that clause).
  def canonical_url(%{character: %Ecto.Association.NotLoaded{}} = object, opts) do
    object =
      warn_and_maybe_preload(object, [character: [:peered]], opts[:preload_if_needed])

    e(object, :character, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object, opts)
  end

  def canonical_url(%{character: %{peered: %{}}} = object, opts) do
    maybe_generate_canonical_url(object, opts)
  end

  # Only for non-actor objects (e.g. a Post): an actor carries its locality on `:peered` under `character` (User/Category, which have a `:character` key) or on its own `:peered` (a bare Character, which has a `:username` key), and for a local actor that `:peered` is legitimately unloaded, so actors skip this tripwire and fall to the `%{peered: %{}}` generate clause below.
  def canonical_url(%{peered: %Ecto.Association.NotLoaded{}} = object, opts)
      when not is_map_key(object, :character) and not is_map_key(object, :username) do
    object =
      warn_and_maybe_preload(object, :peered, opts[:preload_if_needed])

    e(object, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object, opts)
  end

  def canonical_url(%{peered: %{}} = object, opts) do
    maybe_generate_canonical_url(object, opts)
  end

  def canonical_url(%{created: %Ecto.Association.NotLoaded{}} = object, opts) do
    object =
      warn_and_maybe_preload(object, [created: [:peered]], opts[:preload_if_needed])

    e(object, :created, :peered, :canonical_uri, nil) ||
      query_or_generate_canonical_url(object, opts)
  end

  def canonical_url(%{path: "http" <> _ = url} = _object, _opts) do
    url
  end

  def canonical_url(%{path: "/" <> _ = path} = _object, _opts) do
    "#{base_uri()}#{path}"
  end

  def canonical_url("http:" <> _ = url, _opts) do
    url
  end

  def canonical_url("https:" <> _ = url, _opts) do
    url
  end

  def canonical_url("/" <> _ = path, _opts) do
    "#{base_uri()}#{path}"
  end

  def canonical_url(object, opts) do
    query_or_generate_canonical_url(object, opts)
  end

  defp query_or_generate_canonical_url(object, opts) do
    if opts[:preload_if_needed] != false do
      remote_canonical_url(object) ||
        maybe_generate_canonical_url(object, opts)
    else
      if check_is_local?(object, opts), do: maybe_generate_canonical_url(object, opts)
    end
  end

  def remote_canonical_url(object) do
    if module = maybe_module(Bonfire.Federate.ActivityPub.Peered) do
      # debug(object, "attempt to query Peered")
      module.get_canonical_uri(object)
      # |> debug("peered url")
    end
  end

  # Loads `assoc` on demand when it wasn't preloaded upstream, and warns about it unless the caller explicitly opted into lazy loading with `preload_if_needed: true` (so a code path that just forgot to preload at the source is surfaced, while a deliberate lazy caller stays quiet). Returns the object preloaded, unless `preload_if_needed: false` skips the preload and returns it unchanged.
  defp warn_and_maybe_preload(object, assoc, preload_if_needed?) do
    msg = "#{inspect(assoc)} association(s) should be preloaded at the source"

    # when caller knowingly opts in/out → only warn (like skip_err); unset default → err (raises in test)
    if preload_if_needed? in [true, false],
      do: warn(object, msg),
      else: err(object, msg)

    if preload_if_needed? != false,
      do: repo().maybe_preload(object, assoc),
      else: object
  end

  @doc """
  Generates the canonical ActivityPub URL for a local actor or object struct.

  NEW local actors (created after the instance's recorded `:ulid_actor_ids_since` cutoff, auto-recorded at the first boot with this feature by `Bonfire.Common.Settings.IdCutoffs`) federate with a ULID-based actor id (`/pub/person/<ULID>`, `/pub/group/<ULID>`, `/pub/organization/<ULID>`) instead of `/pub/actors/<username>`. Existing actors, and everything when no cutoff is recorded (e.g. in tests unless primed), keep their username URL. WebFinger still advertises `acct:<username>@host` since that handle comes from `preferredUsername`, not the id.

  `opts` is threaded through so `shared_user?/2` can honour `preload_if_needed`, the same lazy-preload pattern the `canonical_url` clauses use for `:peered`.
  """
  def maybe_generate_canonical_url(object, opts \\ [])

  # a bare Character (e.g. an alias target) is the actor mixin of its user: when the `:user` is
  # loaded, take the actor branch with it (so it gets the same URL scheme/id as the actor
  # itself); otherwise we can't name its type and it keeps the legacy username URL — which would
  # DIVERGE from the actor's own canonical id under the new scheme, so preload `:user` at the
  # source wherever a bare Character's URL matters (e.g. `alsoKnownAs` in `format_actor`)
  def maybe_generate_canonical_url(%Bonfire.Data.Identity.Character{} = character, opts) do
    case character do
      %{user: %{id: _} = user} ->
        maybe_generate_canonical_url(Map.put(user, :character, character), opts)

      %{username: username} when is_binary(username) ->
        maybe_generate_canonical_url(username, opts)
    end
  end

  def maybe_generate_canonical_url(%{character: %{username: username}, id: id} = actor, opts)
      when is_binary(username) and is_binary(id) do
    case new_actor_scheme?(id) && actor_type_segment(actor, opts) do
      segment when is_binary(segment) ->
        ap_base_path = Bonfire.Common.Config.get(:ap_base_path, "/pub")
        "#{base_url()}#{ap_base_path}/#{segment}/#{id}"

      _ ->
        # feature off, pre-cutoff actor, or a type we can't name → keep the username URL
        maybe_generate_canonical_url(username, opts)
    end
  end

  def maybe_generate_canonical_url(%{character: %{username: id}}, opts) when is_binary(id) do
    maybe_generate_canonical_url(id, opts)
  end

  def maybe_generate_canonical_url(%{username: id}, opts) when is_binary(id) do
    maybe_generate_canonical_url(id, opts)
  end

  def maybe_generate_canonical_url(%{id: id}, opts) when is_binary(id) do
    maybe_generate_canonical_url(id, opts)
  end

  def maybe_generate_canonical_url(id, _opts) when is_binary(id) do
    ap_base_path = Bonfire.Common.Config.get(:ap_base_path, "/pub")

    if Types.is_uid?(id) do
      "#{base_url()}#{ap_base_path}/objects/#{id}"
    else
      "#{base_url()}#{ap_base_path}/actors/#{id}"
    end
  end

  def maybe_generate_canonical_url(%{"id" => id}, opts),
    do: maybe_generate_canonical_url(id, opts)

  def maybe_generate_canonical_url(%{"username" => id}, opts),
    do: maybe_generate_canonical_url(id, opts)

  def maybe_generate_canonical_url(%{username: id}, opts),
    do: maybe_generate_canonical_url(id, opts)

  def maybe_generate_canonical_url(%{"displayUsername" => id}, opts),
    do: maybe_generate_canonical_url(id, opts)

  def maybe_generate_canonical_url(%{"preferredUsername" => id}, opts),
    do: maybe_generate_canonical_url(id, opts)

  def maybe_generate_canonical_url(_, _opts) do
    nil
  end

  # A local actor uses the ULID scheme iff its id sorts after the instance's recorded cutoff i.e. it was created after this instance first booted with this feature (the cutoff is auto-recorded per instance by `Bonfire.Common.Settings.IdCutoffs`; in test env it defaults to epoch-zero via config/test.exs — see the IdCutoffs moduledoc for how tests override it).
  # Well-known singleton actors (e.g. the service/instance actor, whose hand-crafted id sorts after real ULIDs) are exempted so they always keep their stable username-based URL.
  defp new_actor_scheme?(id) when is_binary(id) do
    Bonfire.Common.Settings.IdCutoffs.after?(:ulid_actor_ids_since, id) and
      id not in Bonfire.Common.Config.get(:reserved_username_actor_ids, [])
  end

  defp new_actor_scheme?(_), do: false

  # The AP-actor-type path segment for a local character struct. Mirrors the federation type mapping: a Category is a Group, a User with a `shared_user` mixin (a team/organisation account) is an Organization, any other User is a Person. Matches the struct module first (fast path); when that doesn't name a type, falls back to `Types.object_type/1` ONCE, because mention resolution and batch actor getters pass (virtual) `%Needle.Pointer{}`s whose concrete type lives in `table_id` — without this they minted username URLs, diverging from the same actor's canonical ULID URL. Returns nil for anything we can't name, so the caller falls back to the username URL rather than minting a mislabelled ULID URL.
  defp actor_type_segment(%{__struct__: module} = actor, opts),
    do: type_segment(module, actor, opts)

  defp actor_type_segment(actor, opts), do: type_segment(nil, actor, opts)

  defp type_segment(Bonfire.Classify.Category, _actor, _opts), do: "group"
  defp type_segment(:topic, _actor, _opts), do: "group"

  defp type_segment(Bonfire.Data.Identity.User, actor, opts),
    do: if(shared_user?(actor, opts), do: "organization", else: "person")

  defp type_segment(module, actor, opts) do
    # e.g. a Pointer: resolve the concrete type from table_id and retry once (`type != module`
    # guards against looping when object_type returns the module we already failed to match)
    case Types.object_type(actor) do
      type when is_atom(type) and not is_nil(type) and type != module ->
        type_segment(type, actor, opts)

      _ ->
        nil
    end
  end

  @doc "True if the given User is an organisation/shared account, i.e. it carries a loaded `shared_user` mixin. If the assoc isn't loaded yet, loads it on demand (unless `preload_if_needed: false`), the same lazy pattern the `canonical_url` clauses use for `:peered`, so callers don't have to remember to preload it."
  def shared_user?(actor, opts \\ [])

  def shared_user?(%{shared_user: %Ecto.Association.NotLoaded{}} = actor, opts) do
    case warn_and_maybe_preload(actor, :shared_user, opts[:preload_if_needed]) do
      # `preload_if_needed: false` left it unloaded, so we can't tell: treat as non-org
      %{shared_user: %Ecto.Association.NotLoaded{}} -> false
      reloaded -> shared_user?(reloaded, opts)
    end
  end

  def shared_user?(%{shared_user: %_{}}, _opts), do: true
  def shared_user?(_, _opts), do: false

  @doc """
  Returns the homepage URI (as struct) of the local instance.

      > %URI{scheme: "http", host: "localhost"} = base_uri(:my_endpoint)

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
  @doc """
  Normalizes local AP (ActivityPub) links in user content to their in-app equivalents, based on format.

  ## Examples

      > normalise_local_links("<a href=\\"http://localhost:4000/pub/actors/foo\\">Actor</a>", :html)
      "<a href=\\"/character/foo\\">Actor</a>"
  """
  def normalise_local_links(input, format)

  def normalise_local_links(input, :html) do
    local_instance = base_url()

    input
    |> Bonfire.Common.Text.as_html_tree()
    |> LazyHTML.Tree.postwalk(fn
      {"a", attrs, children} = node ->
        case List.keyfind(attrs, "href", 0) do
          {"href", href} ->
            new_href =
              href
              |> String.replace_leading(local_instance, "")
              |> localise_ap_path()

            if new_href != href do
              new_attrs = List.keyreplace(attrs, "href", 0, {"href", new_href})
              {"a", new_attrs, children}
            else
              node
            end

          nil ->
            node
        end

      node ->
        node
    end)
  end

  def normalise_local_links(content, :markdown)
      when is_binary(content) and byte_size(content) > 20 do
    local_instance = base_url()

    content
    # handle local AP paths, type-aware via `localise_ap_path/1`
    |> then(
      &Regex.replace(md_ap_paths_regex(local_instance), &1, fn _, pre, path ->
        pre <> localise_ap_path(path)
      end)
    )
    # handle other local links
    |> Regex.replace(md_local_links_regex(local_instance), ..., "\\1\\2")

    # |> debug(content)
  end

  def normalise_local_links(content, _format), do: content

  # Regex patterns for normalizing links (actors: legacy username URLs + new-scheme ULID URLs)
  defp md_ap_paths_regex(local_instance),
    do: ~r/(\()#{local_instance}(\/pub\/(?:actors|person|group|organization|objects)\/.+\))/U

  defp md_local_links_regex(local_instance), do: ~r/(\]\()#{local_instance}(.+\))/U

  @doc """
  Rewrites a local AP path to its in-app equivalent based on the actor/object type in the path, via binary prefix matching (single dispatch, no repeated scans). Unrecognised paths pass through unchanged.

  ## Examples

      iex> localise_ap_path("/pub/actors/alice")
      "/character/alice"

      iex> localise_ap_path("/pub/person/01J3MQ2Q4RVB1WTE3KT1D8ZNX1")
      "/user/01J3MQ2Q4RVB1WTE3KT1D8ZNX1"

      iex> localise_ap_path("/pub/organization/01J3MQ2Q4RVB1WTE3KT1D8ZNX1")
      "/user/01J3MQ2Q4RVB1WTE3KT1D8ZNX1"

      iex> localise_ap_path("/pub/group/01J3MQ2Q4RVB1WTE3KT1D8ZNX1")
      "/group/01J3MQ2Q4RVB1WTE3KT1D8ZNX1"

      iex> localise_ap_path("/pub/objects/01J3MQ2Q4RVB1WTE3KT1D8ZNX1")
      "/discussion/01J3MQ2Q4RVB1WTE3KT1D8ZNX1"

      iex> localise_ap_path("/something/else")
      "/something/else"
  """
  def localise_ap_path("/pub/actors/" <> rest), do: "/character/" <> rest
  def localise_ap_path("/pub/person/" <> rest), do: "/user/" <> rest
  def localise_ap_path("/pub/organization/" <> rest), do: "/user/" <> rest
  def localise_ap_path("/pub/group/" <> rest), do: "/group/" <> rest
  def localise_ap_path("/pub/objects/" <> rest), do: "/discussion/" <> rest
  def localise_ap_path(path), do: path

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
  TODOC
  """
  def based_url(url, conn \\ nil)
  def based_url("http" <> _ = url, _conn), do: url
  def based_url("/" <> url, conn), do: "#{base_url(conn)}/#{url}"
  def based_url(url, _), do: url

  @doc """
  Removes the scheme from a URL to get the display URL.

      iex> display_url("https://example.com/path")
      "example.com/path"

      iex> display_url("http://example.com/path")
      "example.com/path"

      iex> display_url("/path")
      "/path"

  """
  def display_url("https://" <> url), do: url
  def display_url("http://" <> url), do: url
  def display_url(url), do: url

  @doc """
  Generates a static path based on the given path and endpoint module.

      > static_path("/assets/image.png")
      "/assets/image.png"
  """
  def static_path(path, endpoint_module \\ Bonfire.Common.Config.endpoint_module()) do
    endpoint_module.static_path(path)
  end

  def check_is_local?(thing, opts \\ []) do
    Utils.maybe_apply(
      Bonfire.Federate.ActivityPub.AdapterUtils,
      :is_local?,
      [thing, opts],
      Keyword.put_new(opts, :fallback_return, nil)
    )
  end

  def append_params_uri(url_or_uri, params) when is_map(params) or is_list(params) do
    append_params_uri(url_or_uri, params |> Enums.filter_empty_enum(true) |> URI.encode_query())
  end

  def append_params_uri(url_or_uri, params) when is_binary(params) do
    case url_or_uri do
      %URI{} = uri ->
        URI.append_query(uri, params)

      url ->
        URI.append_query(URI.parse(url || ""), params)
    end
  end
end
