defmodule Bonfire.Common.Extend do
  use Arrows
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Me.Settings

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  # TODO: also make it possible to disable individual modules in config?
  """
  def module_enabled?(module, opts \\ []) do
    module_exists?(module) and extension_enabled?(module, opts)
  end

  def module_exists?(module) when is_atom(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, disabled: true`)
  """
  def extension_enabled?(module_or_otp_app, opts \\ []) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)
    context = opts == [] || Utils.current_user(opts) || Utils.current_account(opts)
    # debug(context)
    extension_loaded?(extension) and
      Config.get_ext(extension, :disabled) != true and
      (is_atom(context) or Settings.get([extension, :disabled], nil, context) != true)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present
  """
  def extension_loaded?(module_or_otp_app) when is_atom(module_or_otp_app) do
    extension = maybe_extension_loaded(module_or_otp_app)

    module_exists?(extension) or application_loaded?(extension)
  end

  def application_loaded?(extension) do
    Enum.member?(
      Enum.map(Application.loaded_applications(), &elem(&1, 0)),
      extension
    )
  end

  def maybe_extension_loaded(module_or_otp_app)
      when is_atom(module_or_otp_app) do
    case maybe_module_loaded(module_or_otp_app)
         |> Application.get_application() do
      nil ->
        module_or_otp_app

      # |> debug("received an atom that isn't a module, return it as-is")

      otp_app ->
        otp_app

        # |> debug("#{inspect module_or_otp_app} is a module, so return the corresponding application")
    end
  end

  def maybe_extension_loaded!(module_or_otp_app)
      when is_atom(module_or_otp_app) do
    case maybe_extension_loaded(module_or_otp_app) do
      otp_app when otp_app == module_or_otp_app ->
        application_loaded = application_loaded?(module_or_otp_app)
        # |> debug("is it a loaded application?")

        if application_loaded, do: module_or_otp_app, else: nil

      otp_app ->
        otp_app
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

  defmacro use_if_enabled(module, fallback_module \\ nil),
    do: quoted_use_if_enabled(module, fallback_module, __CALLER__)

  def quoted_use_if_enabled(module, fallback_module \\ nil, caller \\ nil)

  def quoted_use_if_enabled({_, _, _} = module_name_ast, fallback_module, caller),
    do:
      module_name_ast
      |> Macro.expand(caller)
      |> quoted_use_if_enabled(fallback_module)

  # def quoted_use_if_enabled(modules, _fallback_module, _) when is_list(modules) do
  #   debug(modules, "List of modules to use")
  #     quote do
  #       Enum.map(unquote(modules), &use/1)
  #       |> unquote_splicing()
  #     end
  # end

  def quoted_use_if_enabled(module, fallback_module, _) do
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to use: #{module}")
      quote do
        use unquote(module)
      end
    else
      # Logger.debug("Did not find module to use: #{module}")
      if is_atom(fallback_module) and not is_nil(fallback_module) and
           module_enabled?(fallback_module) do
        quote do
          use unquote(fallback_module)
        end
      end
    end
  end

  defmacro import_if_enabled(module, fallback_module \\ nil),
    do: quoted_import_if_enabled(module, fallback_module, __CALLER__)

  def quoted_import_if_enabled(module, fallback_module \\ nil, caller \\ nil)

  def quoted_import_if_enabled({_, _, _} = module_name_ast, fallback_module, caller),
    do:
      quoted_import_if_enabled(
        Macro.expand(module_name_ast, caller),
        fallback_module
      )

  def quoted_import_if_enabled(module, fallback_module, _caller) do
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug(module, "Found module to import")
      quote do
        import unquote(module)
      end
    else
      # Logger.debug(module, "Did not find module to import")

      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          import unquote(fallback_module)
        end
      end
    end
  end

  defmacro require_if_enabled(module, fallback_module \\ nil),
    do: quoted_require_if_enabled(module, fallback_module, __CALLER__)

  def quoted_require_if_enabled(module, fallback_module \\ nil, caller \\ nil)

  def quoted_require_if_enabled({_, _, _} = module_name_ast, fallback_module, caller),
    do:
      quoted_require_if_enabled(
        Macro.expand(module_name_ast, caller),
        fallback_module
      )

  def quoted_require_if_enabled(module, fallback_module, _caller) do
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to require: #{module}")
      quote do
        require unquote(module)
      end
    else
      # Logger.debug("Did not find module to require: #{module}")
      if is_atom(fallback_module) and module_enabled?(fallback_module) do
        quote do
          require unquote(fallback_module)
        end
      end
    end
  end

  # generate an updated reverse router based on extensions that are enabled/disabled
  def generate_reverse_router!() do
    Utils.maybe_apply(Bonfire.Common.Config.endpoint_module(), :generate_reverse_router!)
  end

  def module_file_code(module) do
    code_file =
      module.__info__(:compile)[:source]
      |> to_string()
      |> debug()

    rel_code_file =
      code_file
      |> Path.relative_to(Config.get(:project_path))
      |> debug()

    if Config.get(:env) == :prod do
      # supports doing this in release by using the code in the gzipped code 
      tar_file =
        Path.join(:code.priv_dir(:bonfire), "static/source.tar.gz")
        |> debug()

      with {:error, _} <- Bonfire.Common.Media.read_tar_files(tar_file, rel_code_file) do
        String.replace(code_file, "extensions/", "deps/")
        |> String.replace("forks/", "deps/")
        |> debug()
        |> Bonfire.Common.Media.read_tar_files(tar_file, ...)
      end
    else
      code_file
      |> File.read()
    end
    ~> {:ok, rel_code_file, ...}

    # |> debug()
  end

  def module_code(module) do
    with {:ok, _rel_code_file, code} <- module_file_code(module) do
      {:ok, code}
    end
  end

  def function_line_number(module, fun) when is_atom(module) do
    module_code(module)
    ~> function_line_number(fun)
  end

  def function_line_number(module_code, fun) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
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

  def function_ast(module, fun) do
    module_code(module)
    ~> Code.string_to_quoted!()
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

  def macro_inspect(fun) do
    fun.() |> Macro.expand(__ENV__) |> Macro.to_string() |> debug("Macro")
  end
end
