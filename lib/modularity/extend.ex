defmodule Bonfire.Common.Extend do
  require Logger
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  # TODO: also make it possible to disable individual modules in config
  """
  def module_enabled?(module) do
    module_exists?(module) && extension_enabled?(module)
  end

  def module_exists?(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  """
  def extension_enabled?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)
    extension_loaded?(extension) and !Config.get_ext(extension, :disabled)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present
  """
  def extension_loaded?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)

    module_exists?(extension) or
      Enum.member?(Application.loaded_applications() |> Enum.map(&elem(&1, 0)), extension)
  end

  def maybe_extension_loaded(module_or_otp_app) when is_atom(module_or_otp_app) do
    case maybe_module_loaded(module_or_otp_app) |> Application.get_application() do
      # if we got an otp_app, assume for now that it's valid & loaded
      nil -> module_or_otp_app
      # if we got a module, return the corresponding application
      otp_app -> otp_app
    end
  end


  @doc """
  Whether an Elixir module or extension / OTP app has configuration keys set up
  """
  def has_extension_config?(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)

    config = Application.get_all_env(extension)
    config && config != []
  end


  def maybe_module_loaded(module) do
    if module_exists?(module), do: module
  end

  def maybe_schema_or_pointer(schema_module) do
    module_exists_or(schema_module, Pointers.Pointer)
  end

  def module_exists_or(module, fallback) do
    if module_exists?(module) do
      module
    else
      fallback
    end
  end

  defmacro use_if_enabled(module, fallback_module \\ nil), do: quoted_use_if_enabled(module, fallback_module)

  def quoted_use_if_enabled(module, fallback_module \\ nil)
  def quoted_use_if_enabled({_, _, _} = module_name_ast, fallback_module), do: quoted_use_if_enabled(module_name_ast |> Macro.to_string() |> Utils.maybe_str_to_module(), fallback_module)
  def quoted_use_if_enabled(module, fallback_module) do
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to use: #{module}")
      quote do
        use unquote(module)
      end
    else
      Logger.debug("Did not find module to use: #{module}")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          use unquote(fallback_module)
        end
      end
    end
  end

  defmacro import_if_enabled(module, fallback_module \\ nil), do: quoted_import_if_enabled(module, fallback_module)

  def quoted_import_if_enabled({_, _, _} = module_name_ast, fallback_module), do: quoted_import_if_enabled(module_name_ast |> Macro.to_string() |> Utils.maybe_str_to_module(), fallback_module)
  def quoted_import_if_enabled(module, fallback_module \\ nil) do
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to import: #{module}")
      quote do
        import unquote(module)
      end
    else
      Logger.info("Did not find module to import: #{module}")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          import unquote(fallback_module)
        end
      end
    end
  end

end
