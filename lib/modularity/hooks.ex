defmodule Bonfire.Common.Hooks.Hook do
  @moduledoc """
  Callback module for handling data changes before and after a certain process
  executes.
  """

  @type module_and_fn :: {mod_name :: atom, fn_name :: atom}

  @callback do_before(module_and_fn, data :: any) :: {:ok, any} | {:error, term}
  @callback do_after(module_and_fn, data :: any) :: {:ok, any} | {:error, term}

  defmacro __using__(_opts) do
    quote do
      def do_before(_fn_name, data), do: {:ok, data}
      def do_after(_fn_name, data), do: {:ok, data}

      defoverridable do_before: 2, do_after: 2
    end
  end
end

defmodule Bonfire.Common.Hooks.Target do
  @moduledoc """
  Used by the target of a hook, e.g. a context module, to wrap functions with
  handlers for hooks, calling the before/after functions before and after
  function exection.

  Usage:

  ```elixir
  defmodule MyTarget do
    use Bonfire.Common.Hooks.Target, for: [create: 2]

    def create(user, attrs) do
      {:ok, Map.put(attrs, :read?, true)}
    end
  end
  ```
  """

  # FIXME
  defmacro __using__(for: hook_fns) do
    for {hook_name, arity} = hook_fn <- hook_fns do
      context = __CALLER__.module
      args = Macro.generate_arguments(arity, context)

      if Module.defines?(context, hook_fn) do
        quote context: context do
          def unquote(hook_name)(unquote_splicing(args)) do
            Bonfire.Common.Hooks.run_hooks(unquote(args), :before)

            return = super(unquote_splicing(args))
            Bonfire.Common.Hooks.run_hooks(return, :after)
            return
          end

          defoverridable [unquote(hook_fn)]
        end
      end
    end
  end
end

defmodule Bonfire.Common.Hooks do
  require Logger

  def run_hook(hook_module, data, position) do
    Bonfire.Contexts.run_module_function(
      hook_module,
      position_fn(position),
      [caller(), data],
      &run_hook_function_error/2
    )
  end

  def run_hooks(data, position) do
    hooks = Bonfire.Config.get!([:bonfire, Bonfire.Common.Hooks, :hooks])

    Enum.reduce(hooks, %{ok: [], error: []}, fn mod, acc ->
      case run_hook(mod, data, position) do
        {:ok, ret} ->
          put_in(acc, [:ok, mod], ret)

        {:error, reason} ->
          put_in(acc, [:error, mod], reason)
      end
    end)
  end

  defp position_fn(:before), do: :do_before
  defp position_fn(:after), do: :do_after

  def caller do
    {callingMod, callingFunc, _callingFuncArity, _} =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      |> Enum.fetch!(2)
    {callingMod, callingFunc}
  end

  def run_hook_function_error(error, args, level \\ :error) do
    Logger.log(level, "Bonfire.Common.Hooks: Error running hooked function: #{error} with args: #{inspect args}")

    List.first(args) # return the data passed to the hook to avoid failing on non-existing hooks
  end
end
