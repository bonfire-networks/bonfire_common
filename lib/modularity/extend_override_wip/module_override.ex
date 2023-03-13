defmodule Bonfire.Common.Module.Override do
  @moduledoc """
  Utility to clone a module under a new name
  """

  require Logger

  defmacro __using__(_opts) do
    quote do 
      alias unquote(Bonfire.Common.Module.Override.module_original_name_atom(__CALLER__.module)), as: Original

      import Bonfire.Common.Module.Extend
      # extend the archived module
      extend Original
    end
  end

  @doc """
  Clone the existing module under a new name
  """
  def clone(old_module, new_module) when is_atom(old_module) do
    Logger.info(
      "[Modularity.Module.Override] Cloning module #{module_name_string(old_module)} as #{
        new_module
      }"
    )

    with {:module, _module} <- Code.ensure_compiled(old_module),
         module_source_file = old_module.module_info()[:compile][:source],
         {:ok, f} <- File.read(module_source_file) do
      Code.eval_string(
        String.replace(
          f,
          "defmodule #{module_name_string(old_module)}",
          "defmodule #{module_name_string(new_module)}"
        )
      )

      # returns name of cloned module
      module_name_atom(new_module)
    else
      e ->
        Logger.error("Could not find source of module #{old_module}: #{inspect(e)}")
        nil
    end
  end

  def clone(old_module, new_module) when is_binary(old_module),
    do: clone(String.to_existing_atom(old_module), new_module)

  def clone_original(old_module, prefix \\ nil),
    do: clone(old_module, module_original_name_str(old_module, prefix))

  def module_original_name_str(module, prefix \\ nil), do: "#{prefix || "Original"}.#{module}"
  def module_original_name_atom(module, prefix \\ nil), do: module_original_name_str(module, prefix) |> module_name_atom()

  def module_name_string(module), do: String.replace("#{module}", "Elixir.", "")
  def module_name_atom(module), do: String.to_existing_atom("Elixir.#{module_name_string(module)}")
end
