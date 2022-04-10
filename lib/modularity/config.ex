defmodule Bonfire.Common.Config do
  alias Bonfire.Common.Utils
  import Bonfire.Common.Extend

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
        "You have not configured the `#{extension}` Bonfire extension, please `cp ./deps/#{
          extension
        }/config/#{extension}.exs ./config/#{extension}.exs` in your Bonfire app repository and then customise the copied config as necessary"
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
      get(key, default, top_level_otp_app)
    else
      ret
    end
  end

  def get_ext!(module_or_otp_app, key) do
    case get_ext(module_or_otp_app, key, nil) do
      nil ->
        compilation_error("Missing configuration value: #{inspect([module_or_otp_app, key], pretty: true)}")

      any ->
        any
    end
  end

  @doc """
  Get config value for a config key (optionally from a specific OTP app or Bonfire extension)
  """
  def get(key, default \\ nil, otp_app \\ top_level_otp_app())

  # if no extension is specified, use the top-level Bonfire app
  def get(key, default, nil), do: get(key, default, top_level_otp_app())

  def get([key], default, otp_app), do: get(key, default, otp_app)

  def get([parent_key | keys], default, otp_app) do
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
  Get all config keys/values for a Bonfire extension or OTP app
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

  def put(key, value, nil), do: put(key, value, top_level_otp_app())

  def put([key], value, otp_app), do: put(key, value, otp_app)

  def put([parent_key | keys], value, otp_app) do
    parent =
      get(parent_key, [], otp_app)
      |> put_in(keys, value)

    Application.put_env(otp_app, parent_key, parent, persistent: true)
  end

  def put(key, value, otp_app) do
    Application.put_env(otp_app, key, value, persistent: true)
  end

  def delete(key, otp_app \\ top_level_otp_app())

  def delete([key], otp_app), do: delete(key, otp_app)

  def delete([parent_key | keys], otp_app) do
    {_, parent} =
      get(parent_key, [], otp_app)
      |> get_and_update_in(keys, fn _ -> :pop end)

    Application.put_env(otp_app, parent_key, parent, persistent: true)
  end

  def delete(key, otp_app) do
    Application.delete_env(otp_app, key, persistent: true)
  end

  # some aliases to specific config keys for convienience

  def repo, do: get!(:repo_module)

end

# finally, check that bonfire_common is configured, required so that this module can function
Bonfire.Common.Config.require_extension_config!(:bonfire_common)
