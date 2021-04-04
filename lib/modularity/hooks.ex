defmodule Bonfire.Common.Hooks do
  require Logger

  defmacro hook_ret(ret) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      ret
      |> Bonfire.Common.Hooks.maybe_hook_after(caller)
    end
  end

  defmacro hook_transact_with(fun) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      Bonfire.Repo.transact_with(unquote(fun))
      |> Bonfire.Common.Hooks.maybe_hook_after(caller)
    end
  end

  defmacro hook_undead(socket, fun, return_key \\ :noreply) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      Bonfire.Common.Utils.undead(unquote(socket), unquote(fun), unquote(return_key))
      |> Bonfire.Common.Hooks.maybe_hook_after(caller)
    end
  end

  def maybe_hook_after(ret, caller) do
    case Bonfire.Common.Config.get([:hooks, caller]) do
      {module, fun} ->
        IO.inspect(run_hook_module: module)
        IO.inspect(run_hook_function: fun)
        Bonfire.Contexts.run_module_function(module, fun, ret)
      _ ->
        IO.inspect(no_hook: caller)
        ret
    end
  end

  def caller() do
    {callingMod, callingFunc, callingFuncArity, _} = Process.info(self(), :current_stacktrace) |> elem(1) |> IO.inspect |> Enum.fetch!(2)
    # IO.inspect(callingMod: callingMod)
    # IO.inspect(callingFunc: callingFunc)
    {callingMod, callingFunc, callingFuncArity}
  end

  def run_hook_function_error(error, args, level \\ :error) do
    Logger.log(level, "Bonfire.Common.Hooks: Error running hooked function: #{error} with args: #{inspect args}")

    List.first(args) # return the data passed to the hook to avoid failing on non-existing hooks
  end
end
