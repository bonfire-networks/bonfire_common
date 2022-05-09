defmodule Bonfire.Common.Extend do
  import Where
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  # TODO: also make it possible to disable individual modules in config
  """
  def module_enabled?(module) do
    module_exists?(module) and extension_enabled?(module)
  end

  def module_exists?(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  """
  def extension_enabled?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)
    Config.get_ext(extension, :disabled) != true and extension_loaded?(extension)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present
  """
  def extension_loaded?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)

    module_exists?(extension) or application_loaded?(extension)
  end

  def application_loaded?(extension) do
    Enum.member?(Enum.map(Application.loaded_applications(), &elem(&1, 0)), extension)
  end

  def maybe_extension_loaded(module_or_otp_app) when is_atom(module_or_otp_app) do
    case maybe_module_loaded(module_or_otp_app) |> Application.get_application() do
      nil ->
        module_or_otp_app
        # |> debug("received an atom that isn't a module, return it as-is")

      otp_app ->
        otp_app
        # |> debug("#{inspect module_or_otp_app} is a module, so return the corresponding application")

    end
  end

  def maybe_extension_loaded!(module_or_otp_app) when is_atom(module_or_otp_app) do
    case maybe_extension_loaded(module_or_otp_app) do
      otp_app when otp_app == module_or_otp_app ->

        application_loaded = application_loaded?(module_or_otp_app)
                              # |> debug("is it a loaded application?")

        if application_loaded, do: module_or_otp_app, else: nil

      otp_app ->
        otp_app
    end
  end

  def loaded_deps() do
    if module_enabled?(Mix.Dep) do
      {func, args} = loaded_deps_func_name()
      apply(Mix.Dep, func, args)
      # |> IO.inspect
    else
      # TODO: cache this at compile-time so it is available in releases
      []
    end
  end

  defp loaded_deps_func_name() do
    if Keyword.has_key?(Mix.Dep.__info__(:functions), :cached) do
      {:cached, []}
    else
      {:loaded, [[]]}
    end
  end

  @doc """
  Whether an Elixir module or extension / OTP app has configuration keys set up
  """
  def has_extension_config?(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app) || module_or_otp_app

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
  def quoted_use_if_enabled({_, _, _} = module_name_ast, fallback_module), do: quoted_use_if_enabled(module_name_ast |> Macro.to_string() |> Utils.maybe_to_module(), fallback_module) # TODO: clean this up?
  def quoted_use_if_enabled(module, fallback_module) do
    if is_atom(module) and module_enabled?(module) do
      # debug(module, "Found module to use")
      quote do
        use unquote(module)
      end
    else
      # warn(module, "Did not find module to use")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          use unquote(fallback_module)
        end
      end
    end
  end

  defmacro import_if_enabled(module, fallback_module \\ nil), do: quoted_import_if_enabled(module, fallback_module)

  def quoted_import_if_enabled({_, _, _} = module_name_ast, fallback_module), do: quoted_import_if_enabled(module_name_ast |> Macro.to_string() |> Utils.maybe_to_module(), fallback_module)
  def quoted_import_if_enabled(module, fallback_module \\ nil) do
    if is_atom(module) and module_enabled?(module) do
      # debug(module, "Found module to import")
      quote do
        import unquote(module)
      end
    else
      # warn(module, "Did not find module to import")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          import unquote(fallback_module)
        end
      end
    end
  end

  defmacro require_if_enabled(module, fallback_module \\ nil), do: quoted_require_if_enabled(module, fallback_module)

  def quoted_require_if_enabled({_, _, _} = module_name_ast, fallback_module), do: quoted_require_if_enabled(module_name_ast |> Macro.to_string() |> IO.inspect |> Utils.maybe_to_module() |> IO.inspect, fallback_module)
  def quoted_require_if_enabled(module, fallback_module \\ nil) do
    if is_atom(module) and module_enabled?(module) do
      # debug(module, "Found module to require")
      quote do
        require unquote(module)
      end
    else
      # warn(module, "Did not find module to require")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          require unquote(fallback_module)
        end
      end
    end
  end


end
