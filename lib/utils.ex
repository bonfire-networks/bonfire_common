defmodule Bonfire.Common.Utils do
  import Phoenix.LiveView
  require Logger
  alias Bonfire.Web.Router.Helpers, as: Routes

  def strlen(x) when is_nil(x), do: 0
  def strlen(%{} = obj) when obj == %{}, do: 0
  def strlen(%{}), do: 1
  def strlen(x) when is_binary(x), do: String.length(x)
  def strlen(x) when is_list(x), do: length(x)
  def strlen(x) when x > 0, do: 1
  # let's say that 0 is nothing
  def strlen(x) when x == 0, do: 0

  @doc "Returns a value, or a fallback if not present"
  def e(key, fallback) do
    key || fallback
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e({:ok, map}, key, fallback), do: e(map, key, fallback)

  def e(map, key, fallback) do
    if(is_map(map)) do
      # attempt using key as atom or string, fallback if doesn't exist or is nil
      map_get(map, key, fallback) || fallback
    else
      fallback
    end
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def e(map, key1, key2, fallback) do
    e(e(map, key1, %{}), key2, fallback)
  end

  def e(map, key1, key2, key3, fallback) do
    e(e(map, key1, key2, %{}), key3, fallback)
  end

  def e(map, key1, key2, key3, key4, fallback) do
    e(e(map, key1, key2, key3, %{}), key4, fallback)
  end

  def is_numeric(str) do
    case Float.parse(str) do
      {_num, ""} -> true
      _ -> false
    end
  end

  def to_number(str) do
    case Float.parse(str) do
      {num, ""} -> num
      _ -> 0
    end
  end

  def is_ulid(str) when is_binary(str) do
    with :error <- Pointers.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid(_), do: false

  def ulid(%{id: id}) when is_binary(id), do: ulid(id)
  def ulid(id) do
    if is_ulid(id) do
      id
    else
      Logger.error("Expected ULID ID, got #{inspect id}")
      nil
    end
  end

  @doc """
  Attempt geting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def map_get(map, key, fallback) when is_map(map) and is_atom(key) do
    maybe_get(map, key,
      map_get(map, Atom.to_string(key), fallback)
    ) |> magic_filter_empty(map, key, fallback)
  end

  @doc """
  Attempt geting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback
  """
  def map_get(map, key, fallback) when is_map(map) and is_binary(key) do
    Map.get(
      map,
      key,
      Map.get(
        map,
        Recase.to_camel(key),
        Map.get(
          map,
          maybe_str_to_atom(key),
          fallback
        )
      )
    ) |> magic_filter_empty(map, key, fallback)
  end

  def map_get(map, key, fallback), do: maybe_get(map, key, fallback)

  def maybe_get(_, _, fallback \\ nil)
  def maybe_get(%{} = map, key, fallback), do: Map.get(map, key, fallback) |> magic_filter_empty(map, key, fallback)
  def maybe_get(_, _, fallback), do: fallback

  def magic_filter_empty(%Ecto.Association.NotLoaded{}, %{__struct__: schema} = map, key, fallback \\ nil) when is_map(map) and is_atom(key) do
    if Bonfire.Common.Config.get!(:env) == :dev do
      Logger.error("The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the orginal query...")
      Bonfire.Repo.maybe_preload(map, key) |> Map.get(key, fallback) |> filter_empty(fallback)
    else
      Logger.warn("e() requested #{key} of #{schema} but that was not preloaded in the original query.")
      fallback
    end
  end
  def magic_filter_empty(val, _, _, fallback), do: val |> filter_empty(fallback)

  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback
  def filter_empty(val, fallback), do: val || fallback

  def to_struct(nil, _module) do
    nil
  end

  def put_new_in(%{} = map, [key], val) do
    Map.put_new(map, key, val)
  end

  def put_new_in(%{} = map, [key | path], val) when is_list(path) do
    {_, ret} =
      Map.get_and_update(map, key, fn existing ->
        {val, put_new_in(existing || %{}, path, val)}
      end)

    ret
  end

  @doc "Replace a key in a map"
  def map_key_replace(%{} = map, key, new_key) do
    map
    |> Map.put(new_key, Map.get(map, key))
    |> Map.delete(key)
  end

  def attr_get_id(attrs, field_name) do
    if is_map(attrs) and Map.has_key?(attrs, field_name) do
      attr = Map.get(attrs, field_name)

      maybe_get_id(attr)
    end
  end

  def maybe_get_id(attr) do
    if is_map(attr) and Map.has_key?(attr, :id) do
      attr.id
    else
      attr
    end
  end

  @doc "conditionally update a map"
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "recursively merge maps or lists"
  def deep_merge(left = %{}, right = %{}) do
    Map.merge(left, right, &deep_resolve/3)
  end
  def deep_merge(left = [], right = []) do
    left ++ right
  end

  # Key exists in both maps, and both values are of the same type.
  # These can be merged recursively.
  defp deep_resolve(_key, left = %{}, right = []) do
    deep_merge(left, right)
  end
  defp deep_resolve(_key, left = [], right = []) do
    deep_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map or array. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  def assigns_merge(assigns, map = %{}) do
    assigns
    |> deep_merge(map)
    |> Enum.reject( fn
      {:flash, _} -> true
      _ -> false
    end)
  end

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  @spec maybe_ok_error(any, any) :: any
  @doc "Applies change_fn if the first parameter is an {:ok, val} tuple, else returns the value"
  def maybe_ok_error({:ok, val}, change_fn) do
    {:ok, change_fn.(val)}
  end

  def maybe_ok_error(other, _change_fn), do: other

  @doc "Append an item to a list if it is not nil"
  @spec maybe_append([any()], any()) :: [any()]
  def maybe_append(list, nil), do: list
  def maybe_append(list, value), do: [value | list]

  def maybe_str_to_atom(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> str
    end
  end

  def maybe_atom_to_string(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end
  def maybe_atom_to_string(other) do
    other
  end

  def maybe_struct_to_map(struct = %{__struct__: _}) do
    Map.from_struct(struct)
  end
  def maybe_struct_to_map(other) do
    other
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(map, recursive \\ true)

  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(map = %{}, true) do
    map
    |> maybe_struct_to_map()
    |> Enum.map(fn {k, v} ->
        {
          maybe_atom_to_string(k),
          stringify_keys(v)
        }
      end)
    |> Enum.into(%{})
  end

  def stringify_keys(map = %{}, _) do
    map
    |> maybe_struct_to_map()
    |> Enum.map(fn {k, v} -> {maybe_atom_to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Walk a list and stringify the keys of
  # of any map members
  def stringify_keys([head | rest], recursive) do
    [stringify_keys(head, recursive) | stringify_keys(rest, recursive)]
  end

  def stringify_keys(not_a_map, recursive) do
    not_a_map
  end

  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  def replace_nil(nil, value), do: value
  def replace_nil(other, _), do: other

  def input_to_atoms(%{} = data) do
    data |> Map.new(fn {k, v} -> {maybe_str_to_atom(k), input_to_atoms(v)} end)
  end
  def input_to_atoms(v), do: v

  def random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end

  def r(html), do: Phoenix.HTML.raw(html)

  def markdown(html), do: r(markdown_to_html(html))

  def markdown_to_html(nil) do
    nil
  end

  def markdown_to_html(content) do
    content
    |> Earmark.as_html!()
    |> external_links()
  end

  # open outside links in a new tab
  def external_links(content) do
    Regex.replace(~r/(<a href=\"http.+\")>/U, content, "\\1 target=\"_blank\">")
  end

  def date_from_now(%{id: id}) do
    date_from_pointer(id)
  end

  def date_from_now(date) do
    with {:ok, from_now} <-
           Timex.shift(date, minutes: -3)
           |> Timex.format("{relative}", :relative) do
      from_now
    else
      _ ->
        ""
    end
  end

  def date_from_pointer(id) do
    with {:ok, ts} <- Pointers.ULID.timestamp(id) do
      date_from_now(ts)
    end
  end

  # def paginate_next(fetch_function, %{assigns: assigns} = socket) do
  #   {:noreply, socket |> assign(page: assigns.page + 1) |> fetch_function.(assigns)}
  # end

  # defdelegate content(conn, name, type, opts \\ [do: ""]), to: Bonfire.Common.Web.ContentAreas

  @doc """
  Special LiveView helper function which allows loading LiveComponents in regular Phoenix views: `live_render_component(@conn, MyLiveComponent)`
  """
  def live_render_component(conn, load_live_component) do
    if module_exists?(load_live_component),
      do:
        Phoenix.LiveView.Controller.live_render(
          conn,
          Bonfire.Web.LiveComponent,
          session: %{
            "load_live_component" => load_live_component
          }
        )
  end

  def live_render_with_conn(conn, live_view) do
    Phoenix.LiveView.Controller.live_render(conn, live_view, session: %{"conn" => conn})
  end

  def macro_inspect(fun) do
      fun.() |> Macro.expand(__ENV__) |> Macro.to_string |> IO.inspect(label: "Macro:")
  end

  def module_exists?(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  def module_enabled?(module) do
    # TODO: make it possible to disable extensions (and modules) in config
    module_exists?(module)
  end

  def use_if_available(module, fallback_module \\ nil) do
    if module_enabled?(module) do
      quote do
        use unquote(module)
      end
    else
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          use unquote(fallback_module)
        end
      end
    end
  end

  def import_if_available(module, fallback_module \\ nil) do
    if module_enabled?(module) do
      quote do
        import unquote(module)
      end
    else
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          import unquote(fallback_module)
        end
      end
    end
  end

  def ok(ret, fallback \\ nil) do
    with {:ok, val} <- ret do
      val
    else _ ->
      fallback
    end
  end

  @doc """
  Subscribe to something for realtime updates, like a feed or thread
  """
  def pubsub_subscribe(topics, socket \\ nil) when is_list(topics) do
    Enum.each(topics, &pubsub_subscribe(&1, socket))
  end

  def pubsub_subscribe(topic, socket) when not is_nil(topic) and topic !="" do
    if is_nil(socket) or Phoenix.LiveView.connected?(socket), do:
      Logger.info("pubsub_subscribe: #{inspect topic}")
      Phoenix.PubSub.subscribe(Bonfire.PubSub, topic)
  end

  def pubsub_subscribe(_, _) do
    Logger.info("pubsub did not subscribe")
    false
  end

  @doc """
  Broadcast some data for realtime updates, for example to a feed or thread
  """
  def pubsub_broadcast(topic, {payload_type, _data} = payload) do
    Logger.info("pubsub_broadcast: #{inspect topic} / #{inspect payload_type}")
    Phoenix.PubSub.broadcast(Bonfire.PubSub, topic, payload)
  end
  def pubsub_broadcast(topic, data) when not is_nil(topic) and topic !="" and not is_nil(data) do
    Logger.info("pubsub_broadcast: #{inspect topic}")
    Phoenix.PubSub.broadcast(Bonfire.PubSub, topic, data)
  end
  def pubsub_broadcast(_, _), do: Logger.info("pubsub did not broadcast")


  @doc """
  Run a function and expects tuple.
  If anything else is returned, like an error, a flash message is shown to the user.
  """
  def undead_mount(socket, fun), do: undead(socket, fun, {:mount, :ok})
  def undead_params(socket, fun), do: undead(socket, fun, {:mount, :noreply})

  def undead(socket, fun, return_key \\ :noreply) do
    ret = fun.()

    #IO.inspect(undead_ret: ret)

    case ret do
      {:ok, socket} -> {:ok, socket}
      {:ok, socket, data} -> {:ok, socket, data}
      {:noreply, socket} -> {:noreply, socket}
      {:reply, data, socket} -> {:reply, data, socket}
      {:error, reason} -> live_exception(socket, return_key, reason)
      {:error, reason, extra} -> live_exception(socket, return_key, "#{reason} #{inspect extra}")
      :ok -> {return_key, socket} # shortcut for return nothing
      %Ecto.Changeset{} = cs -> live_exception(socket, return_key, "The data seems invalid and could not be inserted/updated.", cs)
      ret -> live_exception(socket, return_key, "The app returned something unexpected: #{inspect ret}") # TODO: don't show details if not in dev
    end
  rescue
    error in Ecto.Query.CastError ->
      live_exception(socket, return_key, "You seem to have provided an incorrect data type (eg. an invalid ID)", error, __STACKTRACE__)
    error in Ecto.ConstraintError ->
      live_exception(socket, return_key, "You seem to be referencing an invalid object ID, or trying to insert duplicated data", error, __STACKTRACE__)
    error in FunctionClauseError ->
      live_exception(socket, return_key, "A function didn't receive the data it expected", error, __STACKTRACE__)
    cs in Ecto.Changeset ->
        live_exception(socket, return_key, "The data seems invalid and could not be inserted/updated.", cs, nil)
    error ->
      live_exception(socket, return_key, "The app encountered an unexpected error", error, __STACKTRACE__)
  catch
    error ->
      live_exception(socket, return_key, "An exceptional error occured", error, __STACKTRACE__)
  end

  defp live_exception(socket, {:mount, return_key}, msg, exception \\ nil, stacktrace \\ nil, kind \\ :error) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, msg) |> push_redirect(to: "/error")}
    end
  end

  defp live_exception(socket, return_key, msg, exception, stacktrace, kind) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, msg) |> push_patch(to: Routes.live_path(socket, socket.view))}
    end
  rescue
    ArgumentError -> # for cases where the live_path may need param(s) which we don't know about
      {return_key, put_flash(socket, :error, msg) |> push_redirect(to: "/error")}
  end

  defp debug_exception(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  defp debug_exception(%Ecto.Changeset{} = cs, exception, stacktrace, kind) do
    debug_exception(Bonfire.Repo.ChangesetErrors.cs_to_string(cs), exception, stacktrace, kind)
  end

  defp debug_exception(msg, exception, stacktrace, kind) do

    debug_log(msg, exception, stacktrace, kind)

    if Bonfire.Common.Config.get!(:env) == :dev do

      exception = if exception, do: debug_banner(kind, exception, stacktrace)
      stacktrace = if stacktrace, do: Exception.format_stacktrace(stacktrace)

      {:error, Enum.join([msg, exception, stacktrace] |> Enum.filter(& &1), " - ") |> String.slice(0..1000) }
    else
      {:error, msg}
    end
  end

  defp debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error) do

    Logger.error(msg)

    if exception, do: Logger.error(debug_banner(kind, exception, stacktrace))
    # if exception, do: IO.puts(Exception.format_exit(exception))
    if stacktrace, do: Logger.warn(Exception.format_stacktrace(stacktrace))

    if exception && stacktrace && Bonfire.Common.Utils.module_exists?(Sentry), do: Sentry.capture_exception(
      exception,
      stacktrace: stacktrace
    )
  end

  defp debug_banner(kind, %Ecto.Changeset{} = cs, _) do
    Bonfire.Repo.ChangesetErrors.cs_to_string(cs)
  end

  defp debug_banner(kind, exception, stacktrace) do
    if exception && stacktrace, do: inspect Exception.format_banner(kind, exception, stacktrace),
    else: inspect exception
  end

end
