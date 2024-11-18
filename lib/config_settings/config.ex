defmodule Bonfire.Common.Config do
  @moduledoc "Helpers to get app/extension OTP config, or to override a config key. Basically a wrapper of `Application.get_env/3` and `Application.put_env/3`."

  use Bonfire.Common.E
  import Bonfire.Common.Extend
  import Untangle
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Extend
  alias Bonfire.Common.Enums

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
  Raises an error if the specified Bonfire extension is not configured.

  This function checks whether the configuration for a given Bonfire extension exists. If the configuration is missing, it raises a compilation error with a message indicating how to set up the configuration file.

  ## Examples

      iex> require_extension_config!(:some_extension)
      ** (Bonfire.Common.Config.Error) You have not configured the `some_extension` Bonfire extension, please `cp ./deps/some_extension/config/some_extension.exs ./config/some_extension.exs` in your Bonfire app repository and then customise the copied config as necessary

  """
  def require_extension_config!(extension) do
    if !has_extension_config?(extension) do
      compilation_error(
        "You have not configured the `#{extension}` Bonfire extension, please `cp ./deps/#{extension}/config/#{extension}.exs ./config/#{extension}.exs` in your Bonfire app repository and then customise the copied config as necessary"
      )
    end
  end

  @doc """
  Retrieves a configuration value for a specific Bonfire extension or OTP app key.

  This function attempts to get the configuration value for the given key from the specified extension or OTP app. If the key is not found, it falls back to checking the top-level Bonfire app configuration.

  ## Examples

      iex> get_ext(:bonfire_common, :test_key, "default")
      "test_value"

      iex> get_ext(:my_extension, :missing_key, "default")
      "default"

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

  @doc """
  Retrieves the configuration value for a specific Bonfire extension or OTP app key and raises an error if the value is not found.

  This function attempts to get the configuration value for the given key from the specified extension or OTP app. If the key is not present or the value is nil, it raises a compilation error.

  ## Examples

      iex> get_ext!(:bonfire_common, :test_key)
      "test_value"

      iex> get_ext!(:my_extension, :missing_key)
      ** (Bonfire.Common.Config.Error) Missing configuration value: [:my_extension, :missing_key]

  """

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
  Retrieves a configuration value for a key, optionally from a specific OTP app or extension.

  This function can handle single keys or nested key trees and returns the configuration value associated with the key(s). It falls back to a default value if the key is not found.

  ## Examples

      iex> get(:test_key, "default")
      "test_value"

      iex> get([:nested, :key], "default", :bonfire)
      "default"

      iex> get(:missing_key, "default")
      "default"

  """

  def get(key_or_keys, default \\ nil, otp_app \\ nil)

  # if no extension is specified, use the top-level Bonfire app
  def get(keys_tree, default, nil) do
    {otp_app, keys_tree} = keys_tree(keys_tree) |> List.pop_at(0)

    # debug(keys_tree, "Get config for app #{otp_app}")

    get(keys_tree, default, otp_app)
  end

  if Application.compile_env(:bonfire, :env) == :test do
    # NOTE: enables using `ProcessTree` in test env, eg. `Process.put([:bonfire_common, :my_key], :value)`
    def get(keys, default, otp_app) when is_list(keys),
      do: get_for_process([otp_app] ++ keys) || get_config(keys, default, otp_app)

    def get(key, default, otp_app),
      do: get_for_process([otp_app, key]) || get_config(key, default, otp_app)
  else
    def get(keys, default, otp_app), do: get_config(keys, default, otp_app)
  end

  def get_for_process(keys), do: ProcessTree.get(keys)

  defp get_config([key], default, otp_app), do: get_config(key, default, otp_app)

  defp get_config([parent_key | keys], default, otp_app) do
    # debug("get [#{inspect parent_key}, #{inspect keys}] from #{otp_app} or default to #{inspect default}")
    case otp_app
         |> app_get_env(parent_key)
         |> get_in(keys) do
      nil ->
        default

      any ->
        any
    end
  end

  defp get_config(key, default, otp_app) do
    app_get_env(otp_app, key, default)
  end

  defp app_get_env(otp_app, key, default \\ nil) do
    Application.get_env(otp_app, key, default)
  end

  @doc """
  Retrieves the configuration value for a key and raises an error if the value is not found.

  ## Examples

      iex> get!(:test_key)
      "test_value"

      iex> get!(:missing_key, :bonfire_common)
      ** (Bonfire.Common.Config.Error) Missing configuration value: [:bonfire_common, :missing_key]

  """

  def get!(key, otp_app \\ top_level_otp_app()) do
    case get(key, nil, otp_app) do
      nil ->
        compilation_error("Missing configuration value: #{inspect([otp_app, key], pretty: true)}")

      any ->
        any
    end
  end

  @doc """
  Retrieves all configuration keys and values for a specific Bonfire extension or OTP app.

  ## Examples

      > get_ext(:my_extension)
      [key1: "value1", key2: "value2"]

      > get_ext(:another_extension)
      []

  """

  def get_ext(module_or_otp_app) do
    otp_app = maybe_extension_loaded(module_or_otp_app)
    Application.get_all_env(otp_app)
  end

  @doc """
  Retrieves all configuration keys and values for a specific Bonfire extension or OTP app and raises an error if no configuration is found.

  ## Examples

      iex> config = get_ext!(:bonfire_common)
      iex> is_list(config) and config !=[]
      true

      iex> get_ext!(:non_existent_extension)
      ** (Bonfire.Common.Config.Error) Empty configuration for extension: non_existent_extension

  """

  def get_ext!(module_or_otp_app) do
    case get_ext(module_or_otp_app) do
      nil ->
        compilation_error(
          "Missing configuration for extension: #{maybe_extension_loaded(module_or_otp_app)}"
        )

      [] ->
        compilation_error(
          "Empty configuration for extension: #{maybe_extension_loaded(module_or_otp_app)}"
        )

      any ->
        any
    end
  end

  @doc """
  Sets the configuration value for a key or key tree in a specific OTP app or extension.

  This function allows you to set the configuration value for the specified key(s) in the given OTP app or extension. It supports nested configurations.

  ## Examples

      iex> put(:test_key, "test_value")
      :ok

      iex> put([:nested, :key], "test_value", :my_app)
      :ok

  """
  def put(key, value, otp_app \\ nil)

  def put(keys, value, nil) do
    {otp_app, keys_tree} = keys_tree(keys) |> List.pop_at(0)
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
    case Enums.maybe_to_keyword_list(tree, false, false) do
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
          next.(e(data, key, []))

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

  @doc """
  Deletes the configuration value for a key in a specific OTP app or extension.

  This function removes the configuration value for the given key from the specified OTP app or extension.

  ## Examples

      iex> delete(:key)
      :ok

      iex> delete([:nested, :key], :my_app)
      :ok

  """
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
  Constructs a key path for configuration settings, which always starts with an app or extension name. It starts with the main OTP app or extension and includes additional keys as specified.

      > keys_tree([:bonfire_me, Bonfire.Me.Users])
      [:bonfire_me, Bonfire.Me.Users]

      > keys_tree(Bonfire.Me.Users)
      [:bonfire_me, Bonfire.Me.Users]

      > keys_tree(:bonfire_me)
      [:bonfire_me]

      > keys_tree(:random_atom)
      [:bonfire_common, :random_atom]

      >keys_tree([:random_atom, :sub_key])
      [:bonfire_common, :random_atom, :sub_key]
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

  @doc """
  Retrieves the Ecto repository module for the application.

  This function first attempts to fetch the Ecto repository module from the `:ecto_repo_module` key in the process dictionary. If not found, it retrieves the value from the application configuration, and defaults to `Bonfire.Common.Repo` if not configured.

  ## Examples

      iex> repo()
      Bonfire.Common.Repo
  """

  def repo, do: Process.get(:ecto_repo_module) || get(:repo_module, Bonfire.Common.Repo)

  @doc """
  Retrieves the Phoenix endpoint module for the application.

  This function first attempts to fetch the Phoenix endpoint module from the `:phoenix_endpoint_module` key in the process dictionary. If not found, it retrieves the value from the application configuration, defaulting to `Bonfire.Web.Endpoint` if not configured.

  ## Examples

      iex> endpoint_module()
      Bonfire.Web.Endpoint

  """
  def endpoint_module,
    do:
      Process.get(:phoenix_endpoint_module) ||
        get(:endpoint_module, Bonfire.Web.Endpoint)

  @doc """
  Retrieves the environment configuration for the application.

  This function returns the value of the `:env` configuration key for the application.

  ## Examples

      iex> env()
      :test
  """
  def env, do: get(:env)
end

# finally, check that bonfire_common is configured, required so that this module can function
Bonfire.Common.Config.require_extension_config!(:bonfire_common)
