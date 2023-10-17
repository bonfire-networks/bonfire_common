defmodule Bonfire.Common.Config do
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Enums
  import Extend
  import Untangle

  def top_level_otp_app do
    get!(:otp_app, :bonfire_common)
  end

  defmodule Error do
    defexception [:message]
  end

  defmacro compilation_error(error) do
    quote do
      raise(Error, message: unquote(error))
    end
  end

  defdelegate module_enabled?(module), to: Extend

  @doc """
  Stop if an Elixir module or extension / OTP app doesn't have configuration keys set up
  """
  def require_extension_config!(extension) do
    if !has_extension_config?(extension) do
      compilation_error(
        "You have not configured the `#{extension}` Bonfire extension, please `cp ./deps/#{extension}/config/#{extension}.exs ./config/#{extension}.exs` in your Bonfire app repository and then customise the copied config as necessary"
      )
    end
  end

  @doc """
  Get config value for a Bonfire extension or OTP app config key
  """
  def get_ext(module_or_otp_app, key, default \\ nil) do
    otp_app = maybe_extension_loaded(module_or_otp_app)
    top_level_otp_app = top_level_otp_app()
    ret = get(key, default, otp_app)

    if default == ret and otp_app != top_level_otp_app do
      # fallback to checking for the same config in top-level Bonfire app
      get(key, nil, top_level_otp_app) || default
    else
      ret
    end
  end

  def get_ext!(module_or_otp_app, key) do
    case get_ext(module_or_otp_app, key, nil) do
      nil ->
        compilation_error(
          "Missing configuration value: #{inspect([module_or_otp_app, key], pretty: true)}"
        )

      any ->
        any
    end
  end

  @doc """
  Get config value for a config key (optionally from a specific OTP app or Bonfire extension)
  """
  def get(key_or_keys, default \\ nil, otp_app \\ nil)

  # if no extension is specified, use the top-level Bonfire app
  def get(keys_tree, default, nil) do
    {[otp_app], keys_tree} = keys_tree(keys_tree) |> Enum.split(1)
    # debug(keys_tree, "Get config for app #{otp_app}")

    get(keys_tree, default, otp_app)
  end

  def get([key], default, otp_app), do: get(key, default, otp_app)

  def get([parent_key | keys], default, otp_app) do
    # debug("get [#{inspect parent_key}, #{inspect keys}] from #{otp_app} or default to #{inspect default}")
    case otp_app
         |> Application.get_env(parent_key)
         |> get_in(keys) do
      nil ->
        default

      any ->
        any
    end
  end

  def get(key, default, otp_app) do
    Application.get_env(otp_app, key, default)
  end

  def get!(key, otp_app \\ top_level_otp_app()) do
    case get(key, nil, otp_app) do
      nil ->
        compilation_error("Missing configuration value: #{inspect([otp_app, key], pretty: true)}")

      any ->
        any
    end
  end

  @doc """
  Get *all* config keys/values for a specific Bonfire extension or OTP app
  """
  def get_ext(module_or_otp_app) do
    otp_app = maybe_extension_loaded(module_or_otp_app)
    Application.get_all_env(otp_app)
  end

  def get_ext!(module_or_otp_app) do
    case get_ext(module_or_otp_app) do
      nil ->
        compilation_error(
          "Missing configuration for extension #{maybe_extension_loaded(module_or_otp_app)}"
        )

      any ->
        any
    end
  end

  def put(key, value, otp_app \\ nil)

  def put(keys, value, nil) do
    {[otp_app], keys_tree} = keys_tree(keys) |> Enum.split(1)
    # |> debug("otp_app and keys_tree")

    put(keys_tree, value, otp_app)
  end

  def put([key], value, otp_app), do: put(key, value, otp_app)

  def put([parent_key | keys], value, otp_app) do
    # handle nested config
    value =
      get(parent_key, [], otp_app)
      # |> debug("get existing")
      |> put_in(keys_with_fallback(keys), value)

    put_env(otp_app, parent_key, value)
  end

  def put(key, value, otp_app) do
    put_env(otp_app, key, value)
  end

  def put(tree) when is_list(tree) or is_map(tree) do
    Enum.each(tree, &put/1)
  end

  def put({otp_app, tree}) when is_atom(otp_app) and (is_list(tree) or is_map(tree)) do
    Enum.each(tree, fn {k, v} -> put_tree([k], v, otp_app) end)
  end

  def put(other) do
    error(other, "Nothing to put")
  end

  defp put_tree(parent_keys, tree, otp_app) when is_list(tree) do
    if Keyword.keyword?(tree) do
      Enum.each(tree, fn
        {k, v} -> put_tree(parent_keys ++ [k], v, otp_app)
      end)
    else
      put(parent_keys, tree, otp_app)
    end
  end

  defp put_tree(parent_keys, tree, otp_app) when is_map(tree) do
    case Enums.maybe_to_keyword_list(tree) do
      tree when is_list(tree) -> put_tree(parent_keys, tree, otp_app)
      tree -> put(parent_keys, tree, otp_app)
    end
  end

  defp put_tree(k, v, otp_app) do
    # debug(v, inspect k)
    put(k, v, otp_app)
  end

  defp put_env(otp_app, key, value) do
    # debug(value, "#{inspect otp_app}: #{inspect key}")
    Application.put_env(otp_app, key, value, persistent: true)
  end

  defp keys_with_fallback(keys) when is_map(keys),
    do: keys |> Keyword.new(keys) |> keys_with_fallback()

  defp keys_with_fallback(keys) do
    # see https://code.krister.ee/elixir-put_in-deep-empty-map-array/
    access_nil = fn key ->
      fn
        :get, data, next ->
          next.(Utils.e(data, key, []))

        :get_and_update, data, next ->
          data = Keyword.new(data)
          value = Keyword.get(data, key, [])

          case next.(value) do
            {get, update} -> {get, Keyword.put(data, key, update)}
            :pop -> {value, Keyword.delete(data, key)}
          end
      end
    end

    Enum.map(keys, fn k -> access_nil.(k) end)
  end

  def delete(key, otp_app \\ top_level_otp_app())

  def delete([key], otp_app), do: delete(key, otp_app)

  def delete([parent_key | keys], otp_app) do
    {_, parent} =
      get(parent_key, [], otp_app)
      |> get_and_update_in(keys, fn _ -> :pop end)

    put_env(otp_app, parent_key, parent)
  end

  def delete(key, otp_app) do
    Application.delete_env(otp_app, key, persistent: true)
  end

  @doc """
  Constructs a key path for settings/config, which always starts with an app or extension name (which defaults to the main OTP app)

  iex> keys_tree([:bonfire_me, Bonfire.Me.Users])
    [:bonfire_me, Bonfire.Me.Users]

  iex> keys_tree(Bonfire.Me.Users)
    [:bonfire_me, Bonfire.Me.Users]

  iex> keys_tree(:bonfire_me)
    [:bonfire_me]

  iex> keys_tree(:random_atom)
    [:bonfire, :random_atom]

  iex>keys_tree([:random_atom, :sub_key])
    [:bonfire, :random_atom, :sub_key]
  """
  def keys_tree(keys) when is_list(keys) do
    maybe_module_or_otp_app = List.first(keys)

    otp_app = maybe_extension_loaded!(maybe_module_or_otp_app) || top_level_otp_app()

    if maybe_module_or_otp_app != otp_app do
      # add the module name to the key tree
      [otp_app] ++ keys
    else
      keys
    end
  end

  def keys_tree({maybe_module_or_otp_app, tree}) do
    otp_app =
      maybe_extension_loaded!(maybe_module_or_otp_app) ||
        debug(
          top_level_otp_app(),
          "otp_app for #{inspect(maybe_module_or_otp_app)}"
        )

    if maybe_module_or_otp_app != otp_app do
      # add the module name to the key tree
      {otp_app, Map.new([{maybe_module_or_otp_app, tree}])}
    else
      {maybe_module_or_otp_app, tree}
    end
  end

  def keys_tree(key), do: keys_tree([key])

  # some aliases to specific config keys for convienience

  def repo, do: Process.get(:ecto_repo_module) || get(:repo_module, Bonfire.Common.Repo)

  def endpoint_module,
    do:
      Process.get(:phoenix_endpoint_module) ||
        get(:endpoint_module, Bonfire.Web.Endpoint)

  def env, do: get(:env)
end

# finally, check that bonfire_common is configured, required so that this module can function
Bonfire.Common.Config.require_extension_config!(:bonfire_common)
