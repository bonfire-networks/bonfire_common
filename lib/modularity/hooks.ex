defmodule Bonfire.Common.Hooks do
  require Logger

  defmacro hook_ret(ret) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      unquote(ret)
      |> Bonfire.Common.Hooks.maybe_hook(caller, :after)
    end
  end

  defmacro hook_transact_with(fun) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      Bonfire.Common.Hooks.maybe_hook(unquote(fun), caller, :before)
      |> Bonfire.Repo.transact_with()
      |> Bonfire.Common.Hooks.maybe_hook(caller, :after)
    end
  end

  defmacro hook_undead(socket, action, attrs, fun, return_key \\ :noreply) do
    quote do
      caller = Bonfire.Common.Hooks.caller()

      Bonfire.Common.Hooks.maybe_hook([unquote(action), unquote(attrs)], caller, :before)

      Bonfire.Common.Utils.undead(unquote(socket), unquote(fun), unquote(return_key))
      |> Bonfire.Common.Hooks.maybe_hook(caller, :after)
    end
  end

  def maybe_hook(ret, caller, position \\ :after)

  def maybe_hook(ret, caller, position) do
    case Bonfire.Common.Config.get([:hooks, caller], %{}) |> Map.get(position) do
      {module, fun} ->
        IO.inspect(run_hook_module: module)
        IO.inspect(run_hook_function: fun)
        Bonfire.Contexts.run_module_function(module, fun, ret, &run_hook_function_error/2)
      _ ->
        IO.inspect("no hook (#{position}): #{inspect caller}")
        ret
    end
  end

  def caller do
    {callingMod, callingFunc, _callingFuncArity, _} =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      # |> IO.inspect
      |> Enum.fetch!(2)
    # IO.inspect(callingMod: callingMod)
    # IO.inspect(callingFunc: callingFunc)
    # IO.inspect(callingFuncArity: callingFuncArity)
    {callingMod, callingFunc}
  end

  def run_hook_function_error(error, args, level \\ :error) do
    Logger.log(level, "Bonfire.Common.Hooks: Error running hooked function: #{error} with args: #{inspect args}")

    List.first(args) # return the data passed to the hook to avoid failing on non-existing hooks
  end
end