defmodule Bonfire.Common.Extend do
  @moduledoc """
  Helpers for using and managing the extensibility of Bonfire, such as checking if a module or extension is enabled or hot-swapped, or loading code or docs. See also `Bonfire.Common.Extensions`.
  """
  use Arrows
  use Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Opts
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Settings
  alias Bonfire.Common.Cache
  alias Bonfire.Common.Text

  @loaded_apps_names_key {__MODULE__, :loaded_app_names}
  @loaded_apps_key {__MODULE__, :loaded_apps}

  @doc """
  Extend a module by defining `defdelegate` and `defoverridable` for all functions from the source module in the current module.

  ## Examples

      > import Bonfire.Common.Extend
      > extend_module Common.Text
  """
  defmacro extend_module(module) do
    require Logger

    module = Macro.expand(module, __CALLER__)

    Logger.info("[Modularity.Module.Extend] Extending module #{inspect(module)}")

    functions = module.__info__(:functions)

    signatures =
      Enum.map(functions, fn {name, arity} ->
        args =
          if arity == 0 do
            []
          else
            Enum.map(1..arity, fn i ->
              {String.to_atom(<<?x, ?A + i - 1>>), [], nil}
            end)
          end

        {name, [], args}
      end)

    zipped = Enum.zip([signatures, functions])

    for sig_func <- zipped do
      quote do
        Module.register_attribute(__MODULE__, :extend_module, persist: true, accumulate: false)
        @extend_module unquote(module)

        defdelegate unquote(elem(sig_func, 0)), to: unquote(module)
        defoverridable unquote([elem(sig_func, 1)])
      end
    end
  end

  # defmacro extend_module(module \\ nil) do

  #   quote do

  #   caller = __CALLER__.module
  #   module = unquote(module) || Module.get_attribute(caller, :extend_module)

  #   IO.puts("[Bonfire.Common.Extend] Extending module #{inspect(module)} in #{inspect caller}")

  #   functions = module.__info__(:functions)
  #   |> IO.inspect

  #   signatures =
  #     Enum.map(functions, fn {name, arity} ->
  #       args =
  #         if arity == 0 do
  #           []
  #         else
  #           Enum.map(1..arity, fn i ->
  #             {String.to_atom(<<?x, ?A + i - 1>>), [], nil}
  #           end)
  #         end

  #       {name, [], args}
  #     end)
  #   |> IO.inspect

  #   zipped = Enum.zip([signatures, functions])
  #   |> IO.inspect

  #   for sig_func <- zipped do
  #       defdelegate (elem(sig_func, 0)), to: (module)
  #       defoverridable ([elem(sig_func, 1)])
  #     end
  #   end
  # end

  @doc "Make the current module extend another module (i.e. declare `defdelegate` and `defoverridable` for all of that module's functions) "
  # defmacro __using__(opts) do
  #   extend_module()
  # end 

  @doc """
  Given an Elixir module, returns the module if available and not disabled, or its replacement if configured.

  Checks both that module and the extension / OTP app it belongs to are available *and* not disabled (eg. by configuring something like `config :bonfire_common, Bonfire.Common.Text, modularity: :disabled`)

  Important note: you should make sure to use the returned module after calling this function, as it can be different from the one you intended to call, as this allows for swapping out modules in config or user settings (eg. by configuring something like `config :bonfire_common, Bonfire.Common.Text, modularity: MyCustomExtension.Text`) 

  ## Examples

      iex> maybe_module(Bonfire.Common)
      Bonfire.Common

      iex> Config.put(DisabledModule, modularity: :disabled)
      iex> maybe_module(DisabledModule)
      nil

      iex> Config.put([Bonfire.Common.Text], modularity: Bonfire.Common.TextExtended)
      iex> maybe_module(Bonfire.Common.Text)
      Bonfire.Common.TextExtended
      iex> Config.put([Bonfire.Common.Text], modularity: Bonfire.Common.Text)
      iex> maybe_module(Bonfire.Common.Text)
      Bonfire.Common.Text
  """
  def maybe_module(module, opts \\ [])
  def maybe_module(nil, _), do: nil
  def maybe_module(false, _), do: nil

  def maybe_module(module, opts) do
    if module_available?(module) do
      opts =
        Opts.to_options(opts)
        # |> debug()
        |> Keyword.put_new_lazy(:otp_app, fn ->
          maybe_extension_loaded!(module) || Config.top_level_otp_app()
        end)

      modularity = get_modularity(module, opts)

      cond do
        disabled_value?(modularity) ->
          debug(module, "module is disabled")
          nil

        (is_nil(modularity) or modularity == true or modularity == module) and
            do_is_extension_enabled?(opts[:otp_app], opts) ->
          debug(module, "module is not disabled or swapped, and extension is not disabled")
          module

        is_atom(modularity) and module_enabled?(modularity, opts) ->
          debug(
            modularity,
            "module #{module} is swapped, and the replacement module and extension are not disabled"
          )

          modularity

        not is_nil(modularity) ->
          warn(
            modularity,
            "Seems like the replacement module/extension configured for #{module} was itself disabled"
          )

          nil

        true ->
          warn(module, "Seems like the module/extension was not available or disabled")
          nil
      end
    end
  end

  @doc """
  Returns the module if it is present and not disabled; raises an error if the module is disabled and no replacement is configured.

  ## Examples

      iex> maybe_module!(Bonfire.Common)
      Bonfire.Common

      iex> maybe_module!(SomeDisabledModule)
      ** (RuntimeError) Module Elixir.SomeDisabledModule is disabled and no replacement was configured
  """
  def maybe_module!(module, opts \\ []) do
    case maybe_module(module, opts) do
      nil -> raise "Module #{module} is disabled and no replacement was configured"
      module -> module
    end
  end

  @doc """
  Checks if an Elixir module or the extension/OTP app it belongs to is available and not disabled. 

  ## Examples

      iex> module_enabled?(Bonfire.Common)
      true

      iex> module_enabled?(SomeDisabledModule)
      false
  """
  def module_enabled?(module, opts \\ []) do
    opts = Opts.to_options(opts)

    module_available?(module) and
      is_module_extension_enabled?(module, opts) and
      is_disabled?(module, opts) != true
  end

  @doc """
  Checks if an Elixir module exists and that it (or the extension/OTP app it belongs to) is not disabled. 

  ## Examples

      iex> module_enabled?(Bonfire.Common)
      true

      iex> module_enabled?(SomeDisabledModule)
      false
  """
  def module_not_disabled?(module, opts \\ []) do
    opts = Opts.to_options(opts)

    module_exists?(module) and
      is_module_extension_enabled?(module, opts) and
      is_disabled?(module, opts) != true
  end

  # @decorate time()
  @doc """
  Checks if an Elixir module exists and is loaded and that it (or the extension/OTP app it belongs to) is not disabled. 

  ## Examples

      iex> module_available?(Bonfire.Common)
      true

      iex> module_available?(SomeOtherModule)
      false
  """
  def module_available?(module) when is_atom(module) do
    #   Cache.maybe_apply_cached(&do_module_available?/1, [module], check_env: false)
    # end
    # defp do_module_available?(module) when is_atom(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  @doc """
  Checks if an Elixir module exists and can be loaded.

  ## Examples

      iex> module_exists?(Bonfire.Common)
      true

      iex> module_exists?(SomeOtherModule)
      false
  """
  def module_exists?(module) when is_atom(module) do
    #   Cache.maybe_apply_cached(&do_module_exists?/1, [module], check_env: false)
    # end
    # defp do_module_exists?(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        true

      {:error, :unavailable} ->
        true

      {:error, e} ->
        debug(e, "Module `#{module}` is not compiled")
        false
    end
  end

  @doc """
  Checks if an Elixir module or extension/OTP app is present and not disabled.

  For modules, checks also that the extension/OTP app it belongs is not disabled.

  ## Examples

      iex> extension_enabled?(Bonfire.Common)
      true

      iex> extension_enabled?(:bonfire_common)
      true

      iex> extension_enabled?(SomeOtherModule)
      false

      iex> extension_enabled?(:non_existent_extension)
      false
  """
  def extension_enabled?(module_or_otp_app, opts \\ []) when is_atom(module_or_otp_app) do
    opts = Opts.to_options(opts)

    extension = maybe_extension_loaded(module_or_otp_app)
    extension_loaded?(extension) and do_is_extension_enabled?(module_or_otp_app, opts)
  end

  defp is_module_extension_enabled?(module_or_otp_app, opts) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)
    do_is_extension_enabled?(extension, opts)
  end

  defp do_is_extension_enabled?(extension, opts) when is_atom(extension) do
    is_disabled?(extension, opts) != true
  end

  defp get_modularity(module_or_extension, opts) do
    case Keyword.pop(opts, :otp_app) do
      {nil, []} ->
        Config.get([module_or_extension, :modularity], nil)

      {otp_app, []} ->
        if otp_app == module_or_extension do
          Config.get(:modularity, nil, otp_app)
        else
          Config.get([module_or_extension, :modularity], nil, otp_app)
        end

      {otp_app, _opts_with_scope} ->
        opts =
          Keyword.put_new_lazy(opts, :scope, fn ->
            if(!Utils.current_user_id(opts), do: :instance)
          end)

        if otp_app == module_or_extension do
          Settings.get(:modularity, nil, opts)
        else
          Settings.get([module_or_extension, :modularity], nil, opts)
        end
    end
  end

  defp is_disabled?(module_or_extension, opts) do
    get_modularity(module_or_extension, opts)
    |> disabled_value?()
  end

  @doc """
  Checks if a value indicates that a module or extension is disabled.

  ## Examples

      iex> disabled_value?(:disabled)
      true

      iex> disabled_value?(false)
      false

      iex> disabled_value?(disabled: true)
      true
  """
  def disabled_value?(value) do
    case value do
      nil -> false
      false -> false
      :disable -> true
      :disabled -> true
      module when is_atom(module) -> false
      {:disabled, true} -> true
      {:disable, true} -> true
      [disabled: true] -> true
      [disable: true] -> true
      _ -> false
    end
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present
  """
  def extension_loaded?(module_or_otp_app) when is_atom(module_or_otp_app) do
    #   Cache.maybe_apply_cached(&do_extension_loaded?/1, [module_or_otp_app], check_env: false)
    # end
    # defp do_extension_loaded?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)
    module_available?(extension) or application_loaded?(extension)
  end

  @doc """
  Returns the OTP app name for a module or extension.

  ## Examples

      iex> maybe_extension_loaded(Bonfire.Common)
      :bonfire_common

      iex> maybe_extension_loaded(:bonfire_common)
      :bonfire_common

      iex> maybe_extension_loaded(:non_existent_app)
      :non_existent_app
  """
  def maybe_extension_loaded(module_or_otp_app)
      when is_atom(module_or_otp_app) do
    case maybe_module_loaded(module_or_otp_app) do
      nil ->
        module_or_otp_app

      # |> debug("received an atom that isn't a module, return it as-is")

      module ->
        #  debug(module, "it's a module, so return the corresponding application")
        case application_for_module(module) do
          nil ->
            module_or_otp_app

          # |> debug("received an atom that isn't a module, return it as-is")

          otp_app ->
            otp_app

            # |>
        end
    end
  end

  @decorate time()
  @doc """
  Returns the OTP app name for a module or extension if available, and nil otherwise.

  ## Examples

      iex> maybe_extension_loaded!(Bonfire.Common)
      :bonfire_common

      iex> maybe_extension_loaded!(:non_existent_app)
      nil
  """
  def maybe_extension_loaded!(module_or_otp_app)
      when is_atom(module_or_otp_app) do
    case maybe_extension_loaded(module_or_otp_app) do
      otp_app when otp_app == module_or_otp_app ->
        # debug("is it actually a loaded application?")
        if application_loaded?(module_or_otp_app), do: module_or_otp_app, else: nil

      otp_app ->
        otp_app
    end
  end

  @decorate time()
  defp application_loaded?(extension) do
    Map.has_key?(loaded_applications_names(), extension)
  end

  @doc """
  Returns a map of loaded applications names as keys.

  ## Examples

      iex> %{bonfire_common: _} = loaded_applications_names()
      
  """
  def loaded_applications_names(opts \\ [cache: false]) do
    with nil <- :persistent_term.get(@loaded_apps_names_key, nil) do
      uncached_loaded_applications_map(opts)
    end
  end

  @doc """
  Returns a map of loaded applications with their versions and descriptions.

  ## Examples

      iex> %{bonfire_common: {_version, _description} } = loaded_applications_map()

  """
  def loaded_applications_map(opts \\ [cache: false]) do
    with nil <- :persistent_term.get(@loaded_apps_key, nil) do
      uncached_loaded_applications_map(opts)
    end
  end

  defp uncached_loaded_applications_map(opts \\ [cache: false]) do
    apps_map =
      Application.loaded_applications()
      |> prepare_loaded_applications_map()

    if opts[:cache] do
      for {app_name, _} <- apps_map do
        {app_name, true}
      end
      |> Map.new()
      |> info("caching loaded app names")
      |> :persistent_term.put(@loaded_apps_names_key, ...)

      apps_map
      # |> info("caching loaded apps")
      |> :persistent_term.put(@loaded_apps_key, ...)
    end

    apps_map
  end

  defp prepare_loaded_applications_map(applications) when is_list(applications) do
    for {app_name, description, version} <- applications do
      {app_name, {to_string(version), to_string(description)}}
    end
    |> Map.new()

    # |> debug()
  end

  @decorate time()
  @doc """
  Retrieves the OTP application associated with a given module.

  ## Examples

      iex> application_for_module(Bonfire.Common)
      :bonfire_common

      iex> application_for_module(SomeUnknownModule)
      nil
  """
  def application_for_module(module) when is_atom(module) and not is_nil(module) do
    # TODO? would it be more performant to cache the data from `Bonfire.Common.ExtensionBehaviour.app_modules_to_scan` and re-use that here?
    if Code.loaded?(Utils),
      do:
        Cache.maybe_apply_cached({Application, :get_application}, [module],
          force_module: true,
          check_env: false
        ),
      else: Application.get_application(module)
  end

  def application_for_module(module) do
    error(module, "invalid module")
    nil
  end

  @doc """
  Checks whether an Elixir module or extension / OTP app has any configuration available.
  """
  def has_extension_config?(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app) || module_or_otp_app

    config = Application.get_all_env(extension)
    config && config != []
  end

  @doc """
  Checks if a module exists and returns it, otherwise returns nil.

  ## Examples

      iex> maybe_module_loaded(Bonfire.Common)
      Bonfire.Common

      iex> maybe_module_loaded(NonExistentModule)
      nil
  """
  def maybe_module_loaded(module) do
    if module_available?(module), do: module
  end

  @doc """
  Returns the given schema module if it exists, otherwise returns `Needle.Pointer`.

  ## Examples

      > maybe_schema_or_pointer(SomeSchema)
      SomeSchema

      iex> maybe_schema_or_pointer(NonExistentSchema)
      Needle.Pointer
  """
  def maybe_schema_or_pointer(schema_module) do
    maybe_module(schema_module) || Needle.Pointer
  end

  @doc """
  Conditionally uses a module if it's enabled, with an optional fallback.

  ## Examples

      defmodule MyModule do
        use_if_enabled SomeExtension
        # or
        use_if_enabled SomeExtension, [], FallbackModule
      end
  """
  defmacro use_if_enabled(module, opts \\ [], fallback_module \\ nil),
    do: quoted_use_if_enabled(module, opts, fallback_module, __CALLER__)

  def quoted_use_if_enabled(module, opts \\ [], fallback_module \\ nil, caller \\ nil)

  def quoted_use_if_enabled({_, _, _} = module_name_ast, opts, fallback_module, caller),
    do: quoted_use_if_enabled(Macro.expand(module_name_ast, caller), opts, fallback_module)

  # def quoted_use_if_enabled(modules, opts, _fallback_module, _) when is_list(modules) do
  #   debug(modules, "List of modules to use")
  #     quote do
  #       Enum.map(unquote(modules), &use/1)
  #       |> unquote_splicing()
  #     end
  # end

  def quoted_use_if_enabled(module, opts, fallback_module, _) do
    IO.inspect(module)
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      Logger.debug("Found module to use: #{module}")

      quote do
        use unquote(module), unquote(opts)
      end
    else
      Logger.debug("Did not find module to use: #{module}")

      if fallback_module do
        quote do
          use unquote(fallback_module), unquote(opts)
        end
      end
    end
  end

  defmacro use_many_if_enabled(module_configs) when is_list(module_configs) do
    quotes =
      module_configs
      |> IO.inspect(label: "input_modules")
      |> Enum.map(fn
        # Full tuple with module, opts, and fallback as potential AST nodes
        {{_, _, _} = module_ast, opts, fallback} ->
          module = Macro.expand(module_ast, __CALLER__)
          quoted_use_if_enabled(module, opts, fallback)

        # Tuple with just module and opts as potential AST nodes
        {{_, _, _} = module_ast, opts} ->
          module = Macro.expand(module_ast, __CALLER__)
          quoted_use_if_enabled(module, opts, nil)

        # Single module as potential AST node
        {_, _, _} = module_ast ->
          module = Macro.expand(module_ast, __CALLER__)
          quoted_use_if_enabled(module, [], nil)
      end)
      |> IO.inspect(label: "resolved_modules")
      |> Enum.reject(&is_nil/1)

    quote do
      (unquote_splicing(quotes))
    end
  end

  defmacro use_many_if_enabled({_, _, _} = module_configs) do
    quoted_use_many_if_enabled(Macro.expand(module_configs, __CALLER__))
  end

  def quoted_use_many_if_enabled(module_configs) when is_list(module_configs) do
    quotes =
      module_configs
      |> IO.inspect(label: "input_modules")
      |> Enum.map(fn
        # Full tuple with module, opts, and fallback as potential AST nodes
        {module, opts, fallback} ->
          quoted_use_if_enabled(module, opts, fallback)

        # Tuple with just module and opts as potential AST nodes
        {module, opts} ->
          quoted_use_if_enabled(module, opts, nil)

        # Single module as potential AST node
        module ->
          quoted_use_if_enabled(module, [], nil)
      end)
      |> IO.inspect(label: "resolved_modules")
      |> Enum.reject(&is_nil/1)

    quote do
      (unquote_splicing(quotes))
    end
  end

  @doc """
  Conditionally imports a module if it's enabled, with an optional fallback.

  ## Examples

      defmodule MyModule do
        import_if_enabled SomeExtension
        # or
        import_if_enabled SomeExtension, [], FallbackModule
      end
  """
  defmacro import_if_enabled(module, opts \\ [], fallback_module \\ nil),
    do: quoted_import_if_enabled(module, opts, fallback_module, __CALLER__)

  def quoted_import_if_enabled(module, opts \\ [], fallback_module \\ nil, caller \\ nil)

  def quoted_import_if_enabled({_, _, _} = module_name_ast, opts, fallback_module, caller),
    do:
      quoted_import_if_enabled(
        Macro.expand(module_name_ast, caller),
        opts,
        fallback_module
      )

  def quoted_import_if_enabled(module, opts, fallback_module, _caller) do
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug(module, "Found module to import")
      quote do
        import unquote(module), unquote(opts)
      end
    else
      # Logger.debug(module, "Did not find module to import")

      if fallback_module do
        quote do
          import unquote(fallback_module), unquote(opts)
        end
      end
    end
  end

  @doc """
  Conditionally requires a module if it's enabled, with an optional fallback.

  ## Examples

      defmodule MyModule do
        require_if_enabled SomeExtension
        # or
        require_if_enabled SomeExtension, [], FallbackModule
      end
  """
  defmacro require_if_enabled(module, opts \\ [], fallback_module \\ nil),
    do: quoted_require_if_enabled(module, opts, fallback_module, __CALLER__)

  def quoted_require_if_enabled(module, opts \\ [], fallback_module \\ nil, caller \\ nil)

  def quoted_require_if_enabled({_, _, _} = module_name_ast, opts, fallback_module, caller),
    do:
      quoted_require_if_enabled(
        Macro.expand(module_name_ast, caller),
        opts,
        fallback_module
      )

  def quoted_require_if_enabled(module, opts, fallback_module, _caller) do
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to require: #{module}")
      quote do
        require unquote(module), unquote(opts)
      end
    else
      # Logger.debug("Did not find module to require: #{module}")
      if fallback_module do
        quote do
          require unquote(fallback_module), unquote(opts)
        end
      end
    end
  end

  @doc """
  Generates an updated reverse router based on enabled/disabled extensions.

  ## Examples

      > generate_reverse_router!()
      :ok
  """
  def generate_reverse_router!() do
    Utils.maybe_apply(Config.get(:router_module, Bonfire.Web.Router), :generate_reverse_router!, [
      Config.get(:otp_app)
    ])
    |> debug("reverse_router generated?")
  end

  @doc """
  Checks if a module implements a specific behaviour.

  ## Examples

      > module_behaviour?(MyModule, SomeBehaviour)
      true
  """
  def module_behaviour?(module, behaviour) do
    behaviour in module_behaviours(module)
  end

  @doc """
  Returns a list of behaviours implemented by a module.

  ## Examples

      > module_behaviours(MyModule)
      [SomeBehaviour, AnotherBehaviour]
  """
  def module_behaviours(module) do
    (module_available?(module) and
       module.module_info(:attributes)
       |> Keyword.get_values(:behaviour)
       |> List.flatten())
    |> List.wrap()
  end

  @doc """
  Retrieves the file path of the module's source file.

  ## Examples

      > module_file(Bonfire.Common)
      "/path/lib/common.ex"
  """
  def module_file(module) when is_atom(module) and not is_nil(module) do
    if module_available?(module) do
      path =
        module.__info__(:compile)[:source]
        |> to_string()

      if String.ends_with?(path, "/iex") do
        module_file_from_object_code(module)
      else
        path
      end
    else
      module_file_from_object_code(module)
    end
    |> debug()
  end

  def module_file(module) do
    error(module, "Could not get source")
    nil
  end

  @doc """
  Retrieves the source code of a module.

  ## Examples

      > module_file_code(Bonfire.Common)
      "defmodule Bonfire.Common do ... end"
  """
  def module_file_code(module, opts \\ []) do
    prod? = Config.env() == :prod

    opts = opts |> Keyword.put_new(:docs, prod?)

    case module_file(module) do
      nil ->
        with {:ok, code} <- module_beam_code(module, opts) do
          {:ok, nil, code}
        end

      code_file_path ->
        rel_code_file =
          code_file_path
          |> Path.relative_to(Config.get(:project_path) || "./")

        # |> debug()

        cond do
          opts[:from_beam] == true ->
            # re-create a module's code from compiled Beam artifacts
            module_beam_code(module, opts)

          prod? == true ->
            # supports doing this in release by using the code in the gzipped code 

            case tar_file_code(rel_code_file) do
              {:ok, code} ->
                # returns code from file in the gzipped packaged in docker image
                {:ok, return_file(code)}

              _ ->
                # fallback if no archive
                module_beam_code(module, opts)
            end

          true ->
            # dev or test env
            code_file_path
            |> File.read()
        end
        ~> {:ok, rel_code_file, ...}

        # |> debug()
    end
  end

  @doc """
  Returns a string given raw code data.
  """
  def return_file(raw) do
    String.trim(to_string(raw))
  rescue
    e in UnicodeConversionError ->
      warn(e)
      if is_list(raw), do: List.first(raw), else: raw
  end

  @doc """
  Retrieves the content of a code file.

  ## Examples

      > file_code("mix.ex")
      "defmodule ... end"
  """
  def file_code(code_file) do
    case tar_file_code(code_file) do
      {:ok, code} ->
        # returns code from file in the gzipped packaged in docker image
        {:ok, code}

      _ ->
        # fallback if no archive
        code_file
        |> File.read()
    end
  end

  @doc """
  Retrieves the content of a code file within the source code tar file (available in Bonfire prod releases).

  ## Examples

      > tar_file_code("/mix.exs")
      "defmodule ... end"
  """
  def tar_file_code(code_file) do
    with tar_file = Path.join(:code.priv_dir(:bonfire), "static/source.tar.gz"),
         true <- File.exists?(tar_file) || error(tar_file, "Tar file does not exits"),
         {:error, _} <- Bonfire.Common.Media.read_tar_files(tar_file, code_file),
         {:error, _} <-
           code_file
           |> String.replace("extensions/", "deps/")
           |> String.replace("forks/", "deps/")
           # |> debug()
           |> Bonfire.Common.Media.read_tar_files(tar_file, ...) do
      error(code_file, "could not find file in code archive")
    end
  end

  @doc """
  Retrieves the code of a module from the source.

  ## Examples

      > module_code(Bonfire.Common)
      "defmodule Bonfire.Common do ... end"
  """
  def module_code(module, opts \\ []) do
    with {:ok, _rel_code_file, code} <- module_file_code(module, opts) do
      {:ok, code}
    end
  end

  @doc """
  Re-creates a module's code from compiled Beam artifacts.

  ## Examples

      iex> {:ok, _} = module_beam_code(Bonfire.Common)
  """
  def module_beam_code(module, opts \\ []) do
    with {:ok, code} <- BeamFile.elixir_code(module, opts) do
      {:ok, code}
    else
      e ->
        warn(e)
    end
  rescue
    e in ArgumentError ->
      error(e)
      error(__STACKTRACE__)
      nil
  end

  @doc """
  Retrieves the code of a module from its object code.

  ## Examples

      > module_code_from_object_code(Bonfire.Common)
      "defmodule Bonfire.Common do ... end"
  """
  def module_code_from_object_code(module) do
    with {:ok, byte_code} <- module_object_byte_code(module) do
      ast =
        byte_code
        |> debug()
        |> Tuple.to_list()
        |> List.last()

      # |> debug("ast?")

      module_code_from_ast(module, ast)
    else
      e ->
        error(e, "Could not read the compiled hot-swapped code")
    end
  end

  @doc """
  Retrieves the code of a module from its AST (Abstract Syntax Tree).

  ## Examples

      > module_code_from_ast(Bonfire.Common, ast)
      "defmodule Bonfire.Common do ... end"
  """
  def module_code_from_ast(module, ast, target \\ :ast) do
    module_ast_normalize(module, ast, target)
    |> Macro.to_string()
  end

  @doc """
  Normalizes the AST of a module for use.

  ## Examples

      > module_ast_normalize(Bonfire.Common, ast)
  """
  def module_ast_normalize(module, ast, target \\ :ast) do
    BeamFile.Normalizer.normalize(
      {:defmodule, [context: Elixir, import: Kernel],
       [
         {:__aliases__, [alias: false], [module]},
         [do: {:__block__, [], ast}]
       ]},
      target
    )
  end

  @doc """
  Retrieves the file path of a module from its object code.

  ## Examples

      > module_file_from_object_code(Bonfire.Common)
  """
  def module_file_from_object_code(module) do
    with {:ok, byte_code} <- module_object_byte_code(module) do
      case byte_code |> Enum.find_value(& &1[:source]) do
        nil -> error("Could not find a code file for this module")
        path -> path |> to_string()
      end
    end
  end

  @doc """
  Retrieves the beam file path from the object code of a module.

  ## Examples

      > beam_file_from_object_code(Bonfire.Common)
      "/path/ebin/Elixir.Bonfire.Common.beam"
  """
  def beam_file_from_object_code(module) do
    with {_, _code, beam_path} <- module_object_code_tuple(module) do
      beam_path
      |> to_string()
    end
  end

  @doc """
  Retrieves the bytecode of a module's object code.

  ## Examples

      > module_object_byte_code(Bonfire.Common)
      <<...>>
  """
  def module_object_byte_code(module) do
    with {mod, binary, _path} when mod == module <- module_object_code_tuple(module),
         {:ok, byte_code} when mod == module <- BeamFile.byte_code(binary) do
      {:ok, byte_code}
    else
      e ->
        error(e, "Could not read the compiled hot-swapped code")
    end
  end

  @doc """
  Retrieves the object code tuple for a module.

  ## Examples

      iex> {Bonfire.Common, _bytecode, _path} = module_object_code_tuple(Bonfire.Common)
  """
  def module_object_code_tuple(module) do
    :code.get_object_code(module)
  end

  @doc """
  Retrieves the code of a specific function from a module.

  ## Examples

      > function_code(Bonfire.Common, :some_function)
      "def some_function do ... end"
  """
  def function_code(module, fun, opts \\ []) do
    with {:ok, code} <- module_code(module, opts),
         {first_line, last_line} <- function_line_numbers(module, fun, opts) do
      code
      |> Text.split_lines()
      |> Enum.slice((first_line - 1)..(last_line - 1))
      |> Enum.join("\n")
    end
  end

  @doc """
  Return the numbers (as a tuple) of the first and last lines of a function's definition in a module

  ## Examples

      > function_line_numbers(Bonfire.Common, :some_function)
      {10, 20}
  """
  def function_line_numbers(module, fun, opts \\ [])

  def function_line_numbers(module, fun, opts) when is_atom(module) do
    module_code(module, opts)
    ~> function_line_numbers(fun, opts)
  end

  def function_line_numbers(module_code, fun, opts) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
    |> function_line_numbers(fun, opts)
  end

  def function_line_numbers(module_ast, fun, _opts) do
    module_ast
    # |> debug()
    |> Macro.prewalk(nil, fn
      result = {:def, [line: number], [{^fun, _, _} | _]}, acc ->
        {result, acc || number}

      result = {:defp, [line: number], [{^fun, _, _} | _]}, acc ->
        {result, acc || number}

      result = {:def, [line: number], [{:when, _, [{^fun, _, _} | _]} | _]}, acc ->
        {result, acc || number}

      result = {:defp, [line: number], [{:when, _, [{^fun, _, _} | _]} | _]}, acc ->
        {result, acc || number}

      other = {prefix, [line: number], _}, acc when prefix in [:def, :defp] ->
        if acc do
          throw({acc, number - 1})
        else
          {other, acc}
        end

      other, acc ->
        {other, acc}
    end)
  catch
    numbers ->
      numbers
  end

  @doc """
  Returns the line number of the first line where a function is defined in a module.

  ## Examples

      > function_line_number(Bonfire.Common, :some_function)
      10
  """
  def function_line_number(module, fun, opts \\ [])

  def function_line_number(module, fun, opts) when is_atom(module) do
    module_code(module, opts)
    ~> function_line_number(fun, opts)
  end

  def function_line_number(module_code, fun, opts) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
    |> function_line_number(fun, opts)
  end

  def function_line_number(module_ast, fun, _opts) do
    module_ast
    # |> debug()
    |> Macro.prewalk(fn
      {:def, [line: number], [{^fun, _, _} | _]} -> throw(number)
      {:defp, [line: number], [{^fun, _, _} | _]} -> throw(number)
      {:def, [line: number], [{:when, _, [{^fun, _, _} | _]} | _]} -> throw(number)
      {:defp, [line: number], [{:when, _, [{^fun, _, _} | _]} | _]} -> throw(number)
      other -> other
    end)
  catch
    number ->
      number
  end

  @doc """
  Retrieves the AST of a specific function from a module.

  ## Examples

      > function_ast(Bonfire.Common, :some_function)
      [{:def, [...], [...]}, ...]
  """
  def function_ast(module, fun, opts \\ [])

  def function_ast(module, fun, opts) when is_atom(module) do
    with {:ok, code} <- module_code(module, opts) do
      function_ast(code, fun, opts)
    end
  end

  def function_ast(module_code, fun, _opts) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
    # |> debug()
    |> Macro.prewalk([], fn
      result = {:def, _, [{^fun, _, _} | _]}, acc -> {result, acc ++ [result]}
      result = {:defp, _, [{^fun, _, _} | _]}, acc -> {result, acc ++ [result]}
      result = {:def, _, [{:when, _, [{^fun, _, _} | _]} | _]}, acc -> {result, acc ++ [result]}
      result = {:defp, _, [{:when, _, [{^fun, _, _} | _]} | _]}, acc -> {result, acc ++ [result]}
      other, acc -> {other, acc}
    end)
    |> elem(1)
  end

  @doc """
  Copies the code defining a function from its original module to a target module.

  The target module can be specified, otherwise, the function will be injected into a default extension module.

  ## Examples

      iex> inject_function(Common.TextExtended, :blank?)
  """
  def inject_function(module, fun, target_module \\ nil) do
    with module_file when is_binary(module_file) <- module_file(module),
         orig_module when not is_nil(orig_module) <-
           target_module || List.first(module.__info__(:attributes)[:extend_module]) do
      code = function_code(orig_module, fun)

      IO.inspect(code, label: "Injecting the code from `#{orig_module}.#{fun}`")

      inject_before_final_end(module_file, code)
    end
  end

  defp inject_before_final_end(file_path, content_to_inject) do
    file = File.read!(file_path)

    if String.contains?(file, content_to_inject) do
      :ok
    else
      Mix.shell().info([:green, "\n* injecting ", :reset, Path.relative_to_cwd(file_path)])

      content =
        file
        |> String.trim_trailing()
        |> String.trim_trailing("end")
        |> Kernel.<>("\n" <> content_to_inject)
        |> Kernel.<>("\nend\n")

      formatted_content = Code.format_string!(content) |> IO.iodata_to_binary()

      File.write!(file_path, formatted_content)
    end
  end

  @doc """
  Inspects a macro by expanding it and converting it to a string.

  ## Examples

      iex> macro_inspect(fn -> quote do: 1 + 1 end)
      "1 + 1"
  """
  def macro_inspect(fun) do
    fun.() |> Macro.expand(__ENV__) |> Macro.to_string()
    # |> debug("Macro")
  end

  @doc """
  Fetches the `@moduledoc` of a module as a markdown string.

  ## Examples

      > fetch_docs_as_markdown(SomeModule)
      "This is the moduledoc for SomeModule"
  """
  @spec fetch_docs_as_markdown(module()) :: nil | binary()
  def fetch_docs_as_markdown(module) do
    case Code.fetch_docs(module) do
      {:error, :module_not_found} ->
        nil

      {_, _, _, "text/markdown", %{"en" => doc}, _, _} ->
        doc

      _ ->
        nil
    end
  end

  @doc "Fetches `module`.`function`'s @doc as a markdown string"
  @spec fetch_docs_as_markdown(module(), fun()) :: nil | binary()
  def fetch_docs_as_markdown(module, function) do
    case Code.fetch_docs(module) do
      {:error, :module_not_found} ->
        nil

      {_, _, _, "text/markdown", _, _, docs} ->
        Enum.find_value(docs, fn
          {{:function, ^function, _}, _, _, %{"en" => markdown}, %{}} -> markdown
          _ -> nil
        end)
    end
  end

  def deps_tree do
    if function_exported?(Mix.Project, :deps_tree, 0) do
      Mix.Project.deps_tree()
    end
  end

  def deps_tree_flat(tree \\ deps_tree())

  def deps_tree_flat(tree) when is_map(tree) do
    # note that you should call the compile-time cached list in Bonfire.Application
    (Map.values(tree) ++ Map.keys(tree))
    |> List.flatten()
    |> Enum.uniq()
  end

  def deps_tree_flat(_), do: nil
end
