defmodule Bonfire.Common.Extend do
  use Arrows
  require Logger
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Settings

  @doc """
  Extend a module (i.e. define `defdelegate` and `defoverridable` for all functions from the source module in the current module. 
  Usage:
  import Module.Extend
  extend_module Common.Text
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

    zipped = List.zip([signatures, functions])

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

  #   zipped = List.zip([signatures, functions])
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
      Logger.debug("Did not find module to use: #{module}")

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

  def module_file(module) when is_atom(module) do
    module.__info__(:compile)[:source]
    |> to_string()
  end

  def module_file_code(module) do
    code_file_path = module_file(module)

    rel_code_file =
      code_file_path
      |> Path.relative_to(Config.get(:project_path))

    # |> debug()

    if Config.env() == :prod do
      # supports doing this in release by using the code in the gzipped code 
      tar_file = Path.join(:code.priv_dir(:bonfire), "static/source.tar.gz")
      # |> debug()

      with true <- File.exists?(tar_file),
           {:error, _} <- Bonfire.Common.Media.read_tar_files(tar_file, rel_code_file),
           {:error, _} <-
             code_file_path
             |> String.replace("extensions/", "deps/")
             |> String.replace("forks/", "deps/")
             # |> debug()
             |> Bonfire.Common.Media.read_tar_files(tar_file, ...) do
        # supports doing this in release by using the code in the gzipped code 
        BeamFile.elixir_code(module, docs: true)
      else
        {:ok, code} ->
          {:ok, code}

        false ->
          BeamFile.elixir_code(module, docs: true)
      end
    else
      # dev or test env
      code_file_path
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

  def function_code(module, fun) do
    with {:ok, code} <- module_code(module),
         {first_line, last_line} <- function_line_numbers(module, fun) do
      code
      |> split_lines()
      |> Enum.slice((first_line - 1)..(last_line - 1))
      |> Enum.join("\n")
    end
  end

  @doc "Return the numbers (as a tuple) of the first and last lines of a function's definition in a module"
  def function_line_numbers(module, fun) when is_atom(module) do
    module_code(module)
    ~> function_line_numbers(fun)
  end

  def function_line_numbers(module_code, fun) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
    |> function_line_numbers(fun)
  end

  def function_line_numbers(module_ast, fun) do
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

  @doc "Return the number of the first line where a function is defined in a module"
  def function_line_number(module, fun) when is_atom(module) do
    module_code(module)
    ~> function_line_number(fun)
  end

  def function_line_number(module_code, fun) when is_binary(module_code) do
    module_code
    |> Code.string_to_quoted!()
    |> function_line_number(fun)
  end

  def function_line_number(module_ast, fun) do
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

  def function_ast(module, fun) when is_atom(module) do
    with {:ok, code} <- module_code(module) do
      function_ast(code, fun)
    end
  end

  def function_ast(module_code, fun) when is_binary(module_code) do
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
  Copy the code defining a function from its original module to one that extends it (or a manually specified module). 
  Usage: `Module.Extend.inject_function(Common.TextExtended, :blank?)`
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

  def macro_inspect(fun) do
    fun.() |> Macro.expand(__ENV__) |> Macro.to_string() |> debug("Macro")
  end

  def split_lines(string) when is_binary(string),
    do: :binary.split(string, ["\r", "\n", "\r\n"], [:global])
end
