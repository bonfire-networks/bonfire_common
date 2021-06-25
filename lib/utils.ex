defmodule Bonfire.Common.Utils do
  import Phoenix.LiveView
  require Logger
  import Bonfire.Common.URIs
  alias Bonfire.Common.Text
  alias Bonfire.Common.Config
  alias Bonfire.Common.Extend

  defdelegate module_enabled?(module), to: Extend

  def strlen(x) when is_nil(x), do: 0
  def strlen(%{} = obj) when obj == %{}, do: 0
  def strlen(%{}), do: 1
  def strlen(x) when is_binary(x), do: String.length(x)
  def strlen(x) when is_list(x), do: length(x)
  def strlen(x) when x > 0, do: 1
  # let's just say that 0 is nothing
  def strlen(x) when x == 0, do: 0

  @doc "Returns a value, or a fallback if nil/false"
  def e(key, fallback) do
    key || fallback
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e({:ok, object}, key, fallback), do: e(object, key, fallback)

  # def e(object, :current_user = key, fallback) do #temporary
  #       IO.inspect(key: key)
  #       IO.inspect(e_object: object)

  #       case object do
  #     %{__context__: context} ->
  #       IO.inspect(key: key)
  #       IO.inspect(e_context: context)
  #       # try searching in Surface's context (when object is assigns), if present
  #       map_get(object, key, nil) || map_get(context, key, nil) || fallback

  #     map when is_map(map) ->
  #       # attempt using key as atom or string, fallback if doesn't exist or is nil
  #       map_get(map, key, nil) || fallback

  #     list when is_list(list) and length(list)==1 ->
  #       # if object is a list with 1 element, try with that
  #       e(List.first(list), key, nil) || fallback

  #     _ -> fallback
  #   end
  # end

  def e(object, key, fallback) do
    case object do
      %{__context__: context} ->
        # try searching in Surface's context (when object is assigns), if present
        map_get(object, key, nil) || map_get(context, key, nil) || fallback

      map when is_map(map) ->
        # attempt using key as atom or string, fallback if doesn't exist or is nil
        map_get(map, key, nil) || fallback

      list when is_list(list) and length(list)==1 ->
        # if object is a list with 1 element, try with that
        e(List.first(list), key, nil) || fallback

      _ -> fallback
    end
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def e(object, key1, key2, fallback) do
    e(object, key1, %{})
    |> e(key2, fallback)
  end

  def e(object, key1, key2, key3, fallback) do
    e(object, key1, key2, %{})
    |> e(key3, fallback)
  end

  def e(object, key1, key2, key3, key4, fallback) do
    e(object, key1, key2, key3, %{})
    |> e(key4, fallback)
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

  def is_ulid?(str) when is_binary(str) and byte_size(str)==26 do
    with :error <- Pointers.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid?(_), do: false

  def ulid(%{id: id}) when is_binary(id), do: ulid(id)
  def ulid(id) do
    if is_ulid?(id) do
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

  #doc """ Attempt geting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback """
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

  def magic_filter_empty(val, map, key, fallback \\ nil)
  def magic_filter_empty(%Ecto.Association.NotLoaded{}, %{__struct__: schema} = map, key, fallback) when is_map(map) and is_atom(key) do
    if Bonfire.Common.Config.get!(:env) == :dev && Bonfire.Common.Config.get(:e_auto_preload, false) do
      Logger.warn("The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the orginal query...")
      Bonfire.Repo.maybe_preload(map, key) |> Map.get(key, fallback) |> filter_empty(fallback)
    else
      Logger.info("e() requested #{key} of #{schema} but that was not preloaded in the original query.")
      fallback
    end
  end
  def magic_filter_empty(val, _, _, fallback), do: val |> filter_empty(fallback)

  def filter_empty(val, fallback \\ nil)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback
  # def filter_empty(enum, fallback) when is_list(enum) or is_map(enum), do: Enum.map(enum, &filter_empty(&1, fallback))
  def filter_empty(val, fallback), do: val || fallback


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

  @doc "Rename a key in a map"
  def map_key_replace(%{} = map, key, new_key) do
    map
    |> Map.put(new_key, Map.get(map, key))
    |> Map.delete(key)
  end

  def map_key_replace_existing(%{} = map, key, new_key) do
    if Map.has_key?(map, key) do
      map_key_replace(map, key, new_key)
    else
      map
    end
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
  def deep_merge(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right), do: Keyword.merge(left, right), # this includes dups :/ maybe switch to https://github.com/PragTob/deep_merge ?
    else: left ++ right # this includes dups
  end
  def deep_merge(%{} = left, right) when is_list(right) do
    deep_merge(Map.to_list(left), right)
  end
  def deep_merge(left, %{} = right) when is_list(left) do
    deep_merge(left, Map.to_list(right))
  end

  # Key exists in both maps
  # These can be merged recursively.
  defp deep_resolve(_key, left, right) when (is_map(left) or is_list(left)) and (is_map(right) or is_list(right)) do
    deep_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map or array. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end


  def assign_global(socket, assigns) when is_map(assigns), do: assign_global(socket, Map.to_list(assigns))
  def assign_global(socket, assigns) when is_list(assigns) do
    socket
    # being naughty here, let's see how long until Surface breaks it:
    |> Phoenix.LiveView.assign(:__context__,
      Map.get(socket.assigns, :__context__, %{})
      |> Map.merge(maybe_to_map(assigns))
    ) #|> IO.inspect(label: "assign_global")
  end
  def assign_global(socket, {_, _} = assign) do
    assign_global(socket, [assign])
  end
  def assign_global(socket, assign, value) do
    assign_global(socket, {assign, value})
  end
  # def assign_global(socket, assign, value) do
  #   socket
  #   |> Phoenix.LiveView.assign(assign, value)
  #   |> Phoenix.LiveView.assign(:global_assigns, [assign] ++ Map.get(socket.assigns, :global_assigns, []))
  # end

  # TODO: get rid of assigning everything to a component, and then we'll no longer need this
  def assigns_clean(%{} = assigns) when is_map(assigns), do: assigns_clean(Map.to_list(assigns))
  def assigns_clean(assigns) do
    (
    assigns
    ++ [{:current_user, current_user(assigns)}]
    ) # temp workaround
    # |> IO.inspect
    |> Enum.reject( fn
      {key, _} when key in [
        :id,
        :flash,
        :__changed__,
        # :__context__,
        :__surface__,
        :socket
      ] -> true
      _ -> false
    end)
    # |> IO.inspect
  end

  def assigns_minimal(%{} = assigns) when is_map(assigns), do: assigns_minimal(Map.to_list(assigns))
  def assigns_minimal(assigns) do

    preserve_global_assigns = Keyword.get(assigns, :global_assigns, []) || [] #|> IO.inspect

    assigns
    # |> IO.inspect
    |> Enum.reject( fn
      {:current_user, _} -> false
      {:current_account, _} -> false
      {:global_assigns, _} -> false
      {assign, _} -> assign not in preserve_global_assigns
      _ -> true
    end)
    # |> IO.inspect
  end

  def assigns_merge(%Phoenix.LiveView.Socket{} = socket, assigns, new) when is_map(assigns) or is_list(assigns), do: socket |> Phoenix.LiveView.assign(assigns_merge(assigns, new))
  def assigns_merge(assigns, new) when is_map(assigns), do: assigns_merge(Map.to_list(assigns), new)
  def assigns_merge(assigns, new) when is_map(new), do: assigns_merge(assigns, Map.to_list(new))
  def assigns_merge(assigns, new) when is_list(assigns) and is_list(new) do

    assigns
    |> assigns_clean()
    |> deep_merge(new)
    # |> IO.inspect
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
  def maybe_append(list, value) when is_nil(value) or value == [], do: list
  def maybe_append(list, {:ok, value}) when is_nil(value) or value == [], do: list
  def maybe_append(list, value) when is_list(list), do: [value | list]
  def maybe_append(obj, value), do: maybe_append([obj], value)

  def maybe_str_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> str
    end
  end
  def maybe_str_to_atom(other), do: other

  def maybe_str_to_module(str) when is_binary(str) do
    case maybe_str_to_atom(str) do
      module when is_atom(module) -> module
      "Elixir."<>_ -> nil # doesn't exist
      other -> maybe_str_to_module("Elixir."<>str)
    end
  end
  def maybe_str_to_module(atom) when is_atom(atom), do: atom

  def maybe_to_string(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end
  def maybe_to_string(list) when is_list(list) do
    List.to_string(list)
  end
  def maybe_to_string({key, val}) do
    maybe_to_string(key)<>":"<>maybe_to_string(val)
  end
  def maybe_to_string(other) do
    to_string(other)
  end

  @doc """
  Flattens a list by recursively flattening the head and tail of the list
  """
  def flatter(list), do: list |> do_flatter() |> List.flatten()

  defp do_flatter([head | tail]), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter([]), do: []
  defp do_flatter([element]), do: do_flatter(element)
  defp do_flatter({head, tail}), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter(element), do: element

  def struct_to_map(struct = %{__struct__: _}) do
    Map.from_struct(struct) |> Map.drop([:__meta__]) |> map_filter_empty() #|> IO.inspect(label: "clean")
  end
  def struct_to_map(other) do
    other
  end

  def maybe_to_map(obj, recursive \\ false)

  def maybe_to_map(struct = %{__struct__: _}, false) do
    struct_to_map(struct)
  end
  def maybe_to_map(data, false) when is_tuple(data) do
    data
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [a, b] -> {a, b} end)
  end
  def maybe_to_map(data, false) when is_list(data) do
    data
    |> Enum.into(%{})
  end
  def maybe_to_map(other, false) do
    other
  end

  def maybe_to_map(struct = %{__struct__: _}, true) do
    struct_to_map(struct)
    |> maybe_to_map(true)
  end
  def maybe_to_map({a, b}, true) do
    %{a => maybe_to_map(b, true)}
  end
  # def maybe_to_map(data, true) when is_list(data) and length(data)==1 do
  #   data
  #   |> List.first()
  #   |> maybe_to_map(true)
  # end
  def maybe_to_map(data, true) when is_list(data) do
    data
    |> Enum.map(&maybe_to_map(&1, true))
    |> Enum.into(%{})
  end
  def maybe_to_map(other, true) do
    other
  end

  def nested_structs_to_maps(struct = %{__struct__: type}) when type not in [DateTime] do
    struct_to_map(struct) |> nested_structs_to_maps()
  end

  def nested_structs_to_maps(map = %{}) when not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {k, nested_structs_to_maps(v)} end)
    |> Enum.into(%{})
  end

  # def nested_structs_to_maps(v) when is_tuple(v), do: v |> Tuple.to_list()
  def nested_structs_to_maps(v), do: v


  def maybe_merge_to_struct(target, merge) when is_struct(target), do: struct(target, maybe_from_struct(merge))
  def maybe_merge_to_struct(obj1, obj2), do: struct_to_map(Map.merge(obj2, obj1)) # to handle objects queried without schema

  def maybe_from_struct(obj) when is_struct(obj), do: Map.from_struct(obj)
  def maybe_from_struct(obj), do: obj

  def maybe_convert_ulids(list) when is_list(list), do: Enum.map(list, &maybe_convert_ulids/1)

  def maybe_convert_ulids(%{} = map) do
    map |> Enum.map(&maybe_convert_ulids/1) |> Map.new
  end
  def maybe_convert_ulids({key, val}) when byte_size(val) == 16 do
    with {:ok, ulid} <- Pointers.ULID.load(val) do
      {key, ulid}
    else _ ->
      {key, val}
    end
  end
  def maybe_convert_ulids({:ok, val}), do: {:ok, maybe_convert_ulids(val)}
  def maybe_convert_ulids(val), do: val


  def map_filter_empty(data) when is_map(data) and not is_struct(data) do
    Enum.map(data, &map_filter_empty/1) |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  def map_filter_empty({k, v}) do
    {k, map_filter_empty(v)}
  end

  def map_filter_empty(v) do
    filter_empty(v)
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(map, recursive \\ true)

  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(map = %{}, true) do
    map
    |> maybe_to_map()
    |> Enum.map(fn {k, v} ->
        {
          maybe_to_string(k),
          stringify_keys(v)
        }
      end)
    |> Enum.into(%{})
  end

  def stringify_keys(map = %{}, _) do
    map
    |> maybe_to_map()
    |> Enum.map(fn {k, v} -> {maybe_to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Walk a list and stringify the keys of
  # of any map members
  def stringify_keys([head | rest], recursive) do
    [stringify_keys(head, recursive) | stringify_keys(rest, recursive)]
  end

  def stringify_keys(not_a_map, _recursive) do
    not_a_map
  end

  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  def replace_nil(nil, value), do: value
  def replace_nil(other, _), do: other

  def input_to_atoms(%{} = data) do
    # turn any keys into atoms (if such atoms already exist) and discard the rest
    :maps.filter(fn k, _v -> is_atom(k) end,
      data
      |> Map.drop(["_csrf_token"])
      |> Map.new(fn {k, v} -> {maybe_str_to_atom(k), input_to_atoms(v)} end)
    )
  end
  def input_to_atoms(list) when is_list(list), do: Enum.map(list, &input_to_atoms/1)
  def input_to_atoms(v), do: v


  def maybe_to_structs(v), do: v |> input_to_atoms() |> maybe_to_structs_recurse()
  defp maybe_to_structs_recurse(data, parent_id \\ nil)
  defp maybe_to_structs_recurse(%{index_type: type} = data, parent_id) do
    data
    |> Map.new(fn {k, v} -> {k, maybe_to_structs_recurse(v, e(data, :id, nil))} end)
    |> maybe_add_mixin_id(parent_id)
    |> maybe_to_struct(type)
  end
  defp maybe_to_structs_recurse(%{} = data, parent_id) do
    data
    |> Map.new(fn {k, v} -> {k, maybe_to_structs_recurse(v, e(data, :id, nil))} end)
  end
  defp maybe_to_structs_recurse(v, _), do: v

  defp maybe_add_mixin_id(%{id: id} = data, _parent_id) when not is_nil(id), do: data
  defp maybe_add_mixin_id(data, parent_id) when not is_nil(parent_id), do: Map.merge(data, %{id: parent_id})
  defp maybe_add_mixin_id(data, parent_id), do: data

  def maybe_to_struct(obj, type \\ nil)
  def maybe_to_struct(%{__struct__: struct_type} = obj, target_type) when target_type == struct_type, do: obj
  def maybe_to_struct(obj, type) when is_binary(type) do
    case maybe_str_to_module(type) do
      module when is_atom(module) -> maybe_to_struct(obj, module)
      _ -> obj
    end
  end
  def maybe_to_struct(obj, module) when is_atom(module) do
    Logger.info("to_struct")
    # if module_enabled?(module) and module_enabled?(Mappable) do
    #   Mappable.to_struct(obj, module)
    # else
      if module_enabled?(module), do: struct(module, obj),
      else: obj
    # end
  end
  def maybe_to_struct(%{index_type: type} = obj, _type), do: maybe_to_struct(obj, type) # for search results
  def maybe_to_struct(%{__typename: type} = obj, _type), do: maybe_to_struct(obj, type) # for graphql queries
  def maybe_to_struct(obj, _type), do: obj

  def struct_from_map(a_map, as: a_struct) do # MIT licensed function by Kum Sackey
    # Find the keys within the map
    keys = Map.keys(a_struct)
            |> Enum.filter(fn x -> x != :__struct__ end)
    # Process map, checking for both string / atom keys
    processed_map =
    for key <- keys, into: %{} do
        value = Map.get(a_map, key) || Map.get(a_map, to_string(key))
        {key, value}
      end
    a_struct = Map.merge(a_struct, processed_map)
    a_struct
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end

  def r(html), do: Phoenix.HTML.raw(html)

  def md(content), do: r(Text.markdown_to_html(content))

  def rich(nothing) when not is_binary(nothing) or nothing=="" do
    nil
  end
  def rich(content) do
    if is_html?(content), do: r(content),
    else: md(content)
  end


  def is_html?(string) do
    Regex.match?(~r/<\/?[a-z][\s\S]*>/i, string)
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

  def avatar_url(%{profile: %{id: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url
  def avatar_url(%{icon: %{id: _} = media}), do: Bonfire.Files.IconUploader.remote_url(media)
  def avatar_url(%{icon_id: icon_id}) when is_binary(icon_id), do: Bonfire.Files.IconUploader.remote_url(icon_id)
  def avatar_url(%{icon: url}) when is_binary(url), do: url
  def avatar_url(obj), do: image_url(obj)
  # def avatar_url(%{id: id}), do: Bonfire.Me.Fake.avatar_url(id)
  # def avatar_url(_obj), do: Bonfire.Me.Fake.avatar_url()

  def image_url(%{profile: %{id: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url
  def image_url(%{image: %{id: _} = media}), do: Bonfire.Files.ImageUploader.remote_url(media)
  def image_url(%{image_id: image_id}) when is_binary(image_id), do: Bonfire.Files.ImageUploader.remote_url(image_id)
  def image_url(%{image: url}) when is_binary(url), do: url
  def image_url(%{id: id}), do: Bonfire.Me.Fake.avatar_url(id) # FIXME?
  def image_url(_obj), do: Bonfire.Me.Fake.image_url() # FIXME better fallback


  def current_user(%{assigns: assigns} = _socket) do
    current_user(assigns)
  end
  def current_user(%{current_user: current_user} = _assigns) when not is_nil(current_user) do
    current_user
  end
  def current_user(%{__context__: %{current_user: current_user}} = _assigns) when not is_nil(current_user) do
    current_user
  end
  def current_user(%{id: _, profile: _} = current_user) do
    current_user
  end
  def current_user(%{id: _, character: _} = current_user) do
    current_user
  end
  def current_user(_), do: nil


  def current_account(%{assigns: assigns} = _socket) do
    current_account(assigns)
  end
  def current_account(%{current_account: current_account} = _assigns) when not is_nil(current_account) do
    current_account
  end
  def current_account(%{__context__: %{current_account: current_account}} = _assigns) when not is_nil(current_account) do
    current_account
  end
  def current_account(%Bonfire.Data.Identity.Account{id: _} = current_account) do
    current_account
  end
  def current_account(_), do: nil


  # def paginate_next(fetch_function, %{assigns: assigns} = socket) do
  #   {:noreply, socket |> assign(page: assigns.page + 1) |> fetch_function.(assigns)}
  # end

  # defdelegate content(conn, name, type, opts \\ [do: ""]), to: Bonfire.Common.Web.ContentAreas

  @doc """
  Special LiveView helper function which allows loading LiveComponents in regular Phoenix views: `live_render_component(@conn, MyLiveComponent)`
  """
  def live_render_component(conn, load_live_component) do
    if module_enabled?(load_live_component),
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
  # def pubsub_subscribe(topics, socket \\ nil)

  def pubsub_subscribe(topics, socket) when is_list(topics) do
    Enum.each(topics, &pubsub_subscribe(&1, socket))
  end

  def pubsub_subscribe(topic, %Phoenix.LiveView.Socket{} = socket) when is_binary(topic) do
    # IO.inspect(socket)
    if socket_connected_or_user?(socket) do
      pubsub_subscribe(topic)
    else
      Logger.info("PubSub: LiveView is not connected so we skip subscribing to #{inspect topic}")
    end
  end

  def pubsub_subscribe(topic, _) when is_binary(topic), do: pubsub_subscribe(topic)

  def pubsub_subscribe(topic, socket) when not is_binary(topic) do
    with t when is_binary(t) <- maybe_to_string(topic) do
      Logger.info("PubSub: transformed the topic #{inspect topic} into a string we can subscribe to: #{inspect t}")
      pubsub_subscribe(t, socket)
    else _ ->
      Logger.info("PubSub: could not transform the topic into a string we can subscribe to: #{inspect topic}")
    end
  end

  def pubsub_subscribe(topic, _) do
    Logger.info("PubSub can not subscribe to a non-string topic: #{inspect topic}")
    false
  end

  defp pubsub_subscribe(topic) when is_binary(topic) and topic !="" do
    Logger.info("PubSub subscribed to: #{topic}")

    endpoint = Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint)

    # endpoint.unsubscribe(maybe_to_string(topic)) # to avoid duplicate subscriptions?
    endpoint.subscribe(topic)
    # Phoenix.PubSub.subscribe(Bonfire.PubSub, topic)
  end

  defp socket_connected_or_user?(%Phoenix.LiveView.Socket{}), do: true
  defp socket_connected_or_user?(%Bonfire.Data.Identity.User{}), do: true
  defp socket_connected_or_user?(_), do: false

  @doc """
  Broadcast some data for realtime updates, for example to a feed or thread
  """
  def pubsub_broadcast(topic, {payload_type, _data} = payload) do
    Logger.info("pubsub_broadcast: #{inspect topic} / #{inspect payload_type}")
    do_broadcast(topic, payload)
  end
  def pubsub_broadcast(topic, data) when (is_atom(topic) or is_binary(topic)) and topic !="" and not is_nil(data) do
    Logger.info("pubsub_broadcast: #{inspect topic}")
    do_broadcast(topic, data)
  end
  def pubsub_broadcast(_, _), do: Logger.info("pubsub did not broadcast")

  defp do_broadcast(topic, data) do
    # endpoint = Bonfire.Common.Config.get(:endpoint_module, Bonfire.Web.Endpoint)
    # endpoint.broadcast_from(self(), topic, step, state)
    Phoenix.PubSub.broadcast(Bonfire.PubSub, maybe_to_string(topic), data)
  end


  def assigns_subscribe(%Phoenix.LiveView.Socket{} = socket, assign_names) when is_list(assign_names) or is_atom(assign_names) or is_binary(assign_names) do

    # subscribe to god-level assign + object ID based assign if ID provided in tuple
    names_of_assign_topics(assign_names)
    |> pubsub_subscribe(socket)

    socket
    |> self_subscribe(assign_names) # also subscribe to assigns for current user
  end

  @doc "Subscribe to assigns targeted at the current account/user"
  def self_subscribe(%Phoenix.LiveView.Socket{} = socket, assign_names) when is_list(assign_names) or is_atom(assign_names) or is_binary(assign_names) do

    with target_ids when is_list(target_ids) and length(target_ids)>0 <- current_account_and_or_user_ids(socket) do
      target_ids
      |> names_of_assign_topics(assign_names)
      |> pubsub_subscribe(socket)
    else _ ->
      IO.inspect(cannot_self_subscribe: nil)
      # IO.inspect(cannot_self_subscribe: socket)
    end

    socket
  end


  def cast_self(socket, assigns_to_broadcast) do
    assign_target_ids = current_account_and_or_user_ids(socket)

    if assign_target_ids do
      socket |> assign_and_broadcast(assigns_to_broadcast, assign_target_ids)
    else
      Logger.info("cast_self: Cannot send via PubSub without an account and/or user in socket. Falling back to only setting an assign.")
      socket |> assign_global(assigns_to_broadcast)
    end
  end


  @doc "Warning: this will set assigns for any/all users who subscribe to them. You want to `cast_self/2` instead if dealing with user-specific actions or private data."
  def cast_public(socket, assigns_to_broadcast) do
    socket |> assign_and_broadcast(assigns_to_broadcast)
  end


  defp assign_and_broadcast(socket, assigns_to_broadcast, assign_target_ids \\ []) do
    assigns_broadcast(assigns_to_broadcast, assign_target_ids)
    socket |> assign_global(assigns_to_broadcast)
  end

  defp assigns_broadcast(assigns, assign_target_ids \\ [])
  defp assigns_broadcast(assigns, assign_target_ids) when is_list(assigns) do
    Enum.each(assigns, &assigns_broadcast(&1, assign_target_ids))
  end
  # defp assigns_broadcast({{assign_name, assign_id}, data}, assign_target_ids) do
  #   names_of_assign_topics([assign_id] ++ assign_target_ids, assign_name)
  #   |> pubsub_broadcast({:assign, {assign_name, data}})
  # end
  defp assigns_broadcast({assign_name, data}, assign_target_ids) do
    names_of_assign_topics(assign_target_ids, assign_name)
    |> pubsub_broadcast({:assign, {assign_name, data}})
  end

  defp names_of_assign_topics(assign_target_ids \\ [], assign_names)
  defp names_of_assign_topics(assign_target_ids, assign_names) when is_list(assign_names) do
    Enum.map(assign_names, &names_of_assign_topics(assign_target_ids, &1))
  end
  defp names_of_assign_topics(assign_target_ids, {assign_name, assign_id}) do
    names_of_assign_topics([assign_id] ++ assign_target_ids, assign_name)
  end
  defp names_of_assign_topics(assign_target_ids, assign_name) when is_list(assign_target_ids) and length(assign_target_ids)>0 do
    IO.inspect(assign_identified_object: {assign_name, assign_target_ids})
    [{:assign, assign_name}] ++ assign_target_ids
    |> Enum.map(&maybe_to_string/1)
    |> Enum.join(":")
  end
  defp names_of_assign_topics(_, assign_name) do
    IO.inspect(assign_god_level_object: {assign_name})
    {:assign, assign_name}
  end

  def current_account_and_or_user_ids(%{assigns: assigns}), do: current_account_and_or_user_ids(assigns)
  def current_account_and_or_user_ids(%{current_account: %{id: account_id}, current_user: %{id: user_id}}) do
    [{:account, account_id}, {:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_user: %{id: user_id, accounted: %{account_id: account_id}, }}) do
    [{:account, account_id}, {:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_user: %{id: user_id}}) do
    [{:user, user_id}]
  end
  def current_account_and_or_user_ids(%{current_account: %{id: account_id}}) do
    [{:account, account_id}]
  end
  def current_account_and_or_user_ids(%{__context__: context}), do: current_account_and_or_user_ids(context)
  def current_account_and_or_user_ids(_), do: nil


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
      %Ecto.Changeset{} = cs -> live_exception(socket, return_key, "The data provided seems invalid and could not be inserted or updated: "<>Bonfire.Repo.ChangesetErrors.cs_to_string(cs), cs)
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
        live_exception(socket, return_key, "The data provided seems invalid and could not be inserted or updated: "<>Bonfire.Repo.ChangesetErrors.cs_to_string(cs), cs, nil)
    error ->
      live_exception(socket, return_key, "The app encountered an unexpected error", error, __STACKTRACE__)
  catch
    error ->
      live_exception(socket, return_key, "An exceptional error occured", error, __STACKTRACE__)
  end

  defp live_exception(socket, return_key, msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)
  defp live_exception(socket, {:mount, return_key}, msg, exception, stacktrace, kind) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, msg) |> push_redirect(to: "/error")}
    end
  end
  defp live_exception(socket, return_key, msg, exception, stacktrace, kind) do
    with {:error, msg} <- debug_exception(msg, exception, stacktrace, kind) do
      {return_key, put_flash(socket, :error, msg) |> push_patch(to: path(socket.view))}
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

    if exception && stacktrace && Bonfire.Common.Utils.module_enabled?(Sentry), do: Sentry.capture_exception(
      exception,
      stacktrace: stacktrace
    )
  end

  defp debug_banner(_kind, %Ecto.Changeset{} = cs, _) do
    Bonfire.Repo.ChangesetErrors.cs_to_string(cs)
  end

  defp debug_banner(kind, exception, stacktrace) do
    if exception && stacktrace, do: inspect Exception.format_banner(kind, exception, stacktrace),
    else: inspect exception
  end

  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest



  @doc "Helpers for calling hypothetical functions in other modules"
  def maybe_apply(
    module,
    fun,
    args \\ [],
    fallback_fun \\ &apply_error/2
  )

  def maybe_apply(
      module,
      fun,
      args,
      fallback_fun
    )
    when is_atom(module) and is_atom(fun) and is_list(args) and
            is_function(fallback_fun) do

    arity = length(args)

    if module_enabled?(module) do
      if Kernel.function_exported?(module, fun, arity) do
        #IO.inspect(function_exists_in: module)

        try do
          apply(module, fun, args)
        rescue
          e in FunctionClauseError ->
            fallback_fun.(
              "No matching pattern for function #{module}.#{fun}/#{arity} - #{Exception.format_banner(:error, e)}",
              args
            )
        end
      else
        fallback_fun.(
          "No function defined at #{module}.#{fun}/#{arity}",
          args
        )
      end
    else
      fallback_fun.(
        "No such module (#{module}) could be loaded.",
        args
      )
    end
  end

  def maybe_apply(
      module,
      fun,
      args,
      fallback_fun
    )
    when is_atom(module) and is_atom(fun) and
            is_function(fallback_fun), do: maybe_apply(
      module,
      fun,
      [args],
      fallback_fun
    )

  def apply_error(error, args, level \\ :error) do
    Logger.log(level, "maybe_apply: #{error} - with args: (#{inspect args})")

    {:error, error}
  end
end
