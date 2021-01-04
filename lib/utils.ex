defmodule Bonfire.Common.Utils do
  import Phoenix.LiveView
  require Logger

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
    if(strlen(key) > 0) do
      key
    else
      fallback
    end
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e(map, key, fallback) do
    if(is_map(map)) do
      # attempt using key as atom or string
      map_get(map, key, fallback)
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

  @doc """
  Attempt geting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def map_get(map, key, fallback) when is_map(map) and is_atom(key) do
    Map.get(map, key, map_get(map, Atom.to_string(key), fallback))
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
          Map.get(
            map,
            maybe_str_to_atom(Recase.to_camel(key)),
            fallback
          )
        )
      )
    )
  end

  def map_get(map, key, fallback), do: maybe_get(map, key, fallback)

  def maybe_get(_, _, fallback \\ nil)
  def maybe_get(%{} = map, key, fallback), do: Map.get(map, key, fallback)
  def maybe_get(_, _, fallback), do: fallback

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

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

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

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(map, recursive \\ true)

  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(map = %{}, true) do
    map
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), stringify_keys(v)} end)
    |> Enum.into(%{})
  end

  def stringify_keys(map = %{}, _) do
    map
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
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

  def input_to_atoms(data) do
    data |> Map.new(fn {k, v} -> {maybe_str_to_atom(k), v} end)
  end

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

  def paginate_next(fetch_function, %{assigns: assigns} = socket) do
    {:noreply, socket |> assign(page: assigns.page + 1) |> fetch_function.(assigns)}
  end

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

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  def macro_inspect(fun) do
      fun.() |> Macro.expand(__ENV__) |> Macro.to_string |> IO.inspect(label: "Macro:")
  end

  def module_exists?(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end


  def use_if_available(module, fallback_module \\ nil) do
    if module_exists?(module) do
      quote do
        use unquote(module)
      end
    else
      if is_atom(fallback_module) and module_exists?(fallback_module) do
        quote do
          use unquote(fallback_module)
        end
      end
    end
  end

  def import_if_available(module, fallback_module \\ nil) do
    if module_exists?(module) do
      quote do
        import unquote(module)
      end
    else
      if is_atom(fallback_module) and module_exists?(fallback_module) do
        quote do
          import unquote(fallback_module)
        end
      end
    end
  end


end
