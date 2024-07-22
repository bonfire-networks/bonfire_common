defmodule Bonfire.Common.Extend do
  @moduledoc "Helpers for using and managing the extensibility of Bonfire, eg. checking if a module or extension is enabled or hot-swapped, or loading code or docs. See also `Bonfire.Common.Extensions`"

  use Arrows
  require Logger
  use Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Opts
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
  Given an Elixir module, this returns an Elixir module, as long as the module and extension / OTP app is present AND not disabled (eg. by having in config something like `config Bonfire.Common.Text, modularity: :disabled`)

  Important note: you should make sure to use the returned module, rather than the one provided as argument, as it can be different, this allows for swapping out modules in config or user settings (eg. by having in config something like `config Bonfire.Common.Text, modularity: MyCustomExtension.Text`) 
  """
  def maybe_module(module, opts \\ [])
  def maybe_module(nil, _), do: nil
  def maybe_module(false, _), do: nil

  def maybe_module(module, opts) do
    if module_exists?(module) do
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

  def maybe_module!(module, opts \\ []) do
    case maybe_module(module, opts) do
      nil -> raise "Module #{module} is disabled and no replacement was configured"
      module -> module
    end
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not disabled (eg. by having in config something like `config :bonfire_common, modularity: :disabled`)
  """
  def module_enabled?(module, opts \\ []) do
    opts = Opts.to_options(opts)

    module_exists?(module) and
      is_module_extension_enabled?(module, opts) and
      is_disabled?(module, opts) != true
  end

  @decorate time()
  def module_exists?(module) when is_atom(module) do
    function_exported?(module, :__info__, 1) || Code.ensure_loaded?(module)
  end

  @doc """
  Whether an Elixir module or extension / OTP app is present AND not part of a disabled Bonfire extension (by having in config something like `config :bonfire_common, modularity: :disabled`)
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
    extension = maybe_extension_loaded(module_or_otp_app)

    module_exists?(extension) or application_loaded?(extension)
  end

  def maybe_extension_loaded(module_or_otp_app)
      when is_atom(module_or_otp_app) do
    case maybe_module_loaded(module_or_otp_app)
         |> application_for_module() do
      nil ->
        module_or_otp_app

      # |> debug("received an atom that isn't a module, return it as-is")

      otp_app ->
        otp_app

        # |> debug("#{inspect module_or_otp_app} is a module, so return the corresponding application")
    end
  end

  @decorate time()
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
    loaded_apps = Application.loaded_applications()
    app_names = Enum.map(loaded_apps, &elem(&1, 0))

    Enum.member?(
      app_names,
      extension
    )
  end

  @decorate time()
  defp application_for_module(module) do
    Application.get_application(module)
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
    maybe_module(schema_module) || Needle.Pointer
  end

  defmacro use_if_enabled(module, fallback_module \\ nil),
    do: quoted_use_if_enabled(module, fallback_module, __CALLER__)

  def quoted_use_if_enabled(module, fallback_module \\ nil, caller \\ nil)

  def quoted_use_if_enabled({_, _, _} = module_name_ast, fallback_module, caller),
    do: quoted_use_if_enabled(Macro.expand(module_name_ast, caller), fallback_module)

  # def quoted_use_if_enabled(modules, _fallback_module, _) when is_list(modules) do
  #   debug(modules, "List of modules to use")
  #     quote do
  #       Enum.map(unquote(modules), &use/1)
  #       |> unquote_splicing()
  #     end
  # end

  def quoted_use_if_enabled(module, fallback_module, _) do
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to use: #{module}")
      quote do
        use unquote(module)
      end
    else
      Logger.debug("Did not find module to use: #{module}")

      if fallback_module do
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
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug(module, "Found module to import")
      quote do
        import unquote(module)
      end
    else
      # Logger.debug(module, "Did not find module to import")

      if fallback_module do
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
    # if module = maybe_module(module) && Code.ensure_loaded?(module) do # TODO
    if is_atom(module) and module_enabled?(module) do
      # Logger.debug("Found module to require: #{module}")
      quote do
        require unquote(module)
      end
    else
      # Logger.debug("Did not find module to require: #{module}")
      if fallback_module do
        quote do
          require unquote(fallback_module)
        end
      end
    end
  end

  # generate an updated reverse router based on extensions that are enabled/disabled
  def generate_reverse_router!() do
    Utils.maybe_apply(Bonfire.Common.Config.endpoint_module(), :generate_reverse_router!)
    |> debug("reverse_router generated?")
  end

  def module_file(module) when is_atom(module) and not is_nil(module) do
    if module_exists?(module) do
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
          |> Path.relative_to(Config.get(:project_path))

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

  def return_file(raw) do
    String.trim(to_string(raw))
  rescue
    e in UnicodeConversionError ->
      warn(e)
      if is_list(raw), do: List.first(raw), else: raw
  end

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

  def module_code(module, opts \\ []) do
    with {:ok, _rel_code_file, code} <- module_file_code(module, opts) do
      {:ok, code}
    end
  end

  @doc "re-create a module's code from compiled Beam artifacts"
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

  def module_code_from_ast(module, ast, target \\ :ast) do
    module_ast_normalize(module, ast, target)
    |> Macro.to_string()
  end

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

  def module_file_from_object_code(module) do
    with {:ok, byte_code} <- module_object_byte_code(module) do
      case byte_code |> Enum.find_value(& &1[:source]) do
        nil -> error("Could not find a code file for this module")
        path -> path |> to_string()
      end
    end
  end

  def beam_file_from_object_code(module) do
    with {_, _code, beam_path} <- module_object_code_tuple(module) do
      beam_path
      |> to_string()
    end
  end

  def module_object_byte_code(module) do
    with {mod, binary, _path} when mod == module <- module_object_code_tuple(module),
         {:ok, byte_code} when mod == module <- BeamFile.byte_code(binary) do
      {:ok, byte_code}
    else
      e ->
        error(e, "Could not read the compiled hot-swapped code")
    end
  end

  def module_object_code_tuple(module) do
    :code.get_object_code(module)
  end

  def function_code(module, fun, opts \\ []) do
    with {:ok, code} <- module_code(module, opts),
         {first_line, last_line} <- function_line_numbers(module, fun, opts) do
      code
      |> split_lines()
      |> Enum.slice((first_line - 1)..(last_line - 1))
      |> Enum.join("\n")
    end
  end

  @doc "Return the numbers (as a tuple) of the first and last lines of a function's definition in a module"
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

  @doc "Return the number of the first line where a function is defined in a module"
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

  @doc "Fetches `module`'s @moduledoc as a markdown string"
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
end
