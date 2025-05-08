# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ConfigSettingsRegistration do
  @moduledoc """
  Shared functionality for registering configuration and settings keys at compile time.
  """
  use Untangle
  alias Bonfire.Common.Extend

  @doc """
  Create a registration map based on the specified order of keys.
  """
  def create_registration_map(keys_order, a, b, c) do
    case keys_order do
      {:keys, :default, :opts} ->
        %{
          keys: a,
          default: b,
          opts: c
        }

      {:keys, :opts, :default} ->
        %{
          keys: a,
          default: c,
          opts: b
        }

      {:keys, :default, :app} ->
        %{
          app: c,
          keys: a,
          default: b
        }

      {:keys, :app, :default} ->
        %{
          app: b,
          keys: a,
          default: c
        }

      {:app, :keys, :default} ->
        %{
          app: a,
          keys: b,
          default: c
        }

      # Fallback to a simple positional approach if all else fails
      _ ->
        %{
          a: a,
          b: b,
          c: c
        }
    end
  end

  @doc """
  Register a key at compile time.
  """
  def register_key(type, keys_order, a, b, c, caller) do
    # debug(type, "Registering key")
    # Create registration entry
    registration =
      create_registration_map(keys_order, a, b, c)
      |> Map.merge(%{
        type: type,
        env: Macro.Env.prune_compile_info(caller)
        # module: caller.module,
        # file: caller.file,
        # line: caller.line,
        # function: caller.function
        # timestamp: DateTime.utc_now()
      })

    # Store in module attribute
    Module.put_attribute(caller.module, :bonfire_config_keys, registration)
  end

  @doc """
  Create a macro that registers keys and delegates to implementation.
  """
  defmacro def_registered_macro(macro_name, fn_name, type, keys_order, module) do
    quote do
      # Define the macros that registers and delegates
      defmacro unquote(macro_name)(a, b \\ nil, c \\ nil) do
        # Register at compile time
        Bonfire.Common.ConfigSettingsRegistration.register_key(
          unquote(type),
          unquote(keys_order),
          a,
          b,
          c,
          __CALLER__
        )

        # Capture the variables in this scope for use in the inner quote
        mod = unquote(module)
        fun = unquote(fn_name)

        # Delegate to implementation
        quote do
          apply(unquote(mod), unquote(fun), [unquote(a), unquote(b), unquote(c)])
        end
      end
    end
  end

  @doc """
  Module attribute initialization for config/settings modules.
  """
  defmacro __using__(_opts) do
    quote do
      # NOTE: we nest the __using__ because this code should be included in the modules that use the Config or Settings modules
      defmacro __using__(_opts) do
        called_in_module? = not is_nil(__CALLER__.module)

        quote do
          # use Bonfire.Common.Localise
          alias Bonfire.Common.Config
          alias Bonfire.Common.Settings

          if unquote(called_in_module?) do
            # Set up the module attribute to collect keys
            Module.register_attribute(__MODULE__, :bonfire_config_keys, accumulate: true)

            # Define a function to retrieve the keys at runtime

            @before_compile Bonfire.Common.ConfigSettingsRegistration
          end
        end
      end
    end
  end

  @doc """
  Before compile hook to add __bonfire_config_keys__ function.
  """
  defmacro __before_compile__(_env) do
    quote do
      def __bonfire_config_keys__ do
        @bonfire_config_keys
      end
    end
  end
end
