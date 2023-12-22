# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ExtensionBehaviour do
  @moduledoc """
  A Global cache of known Behaviours in Bonfire

  Use of the ExtensionBehaviour Service requires declaring `@behaviour Bonfire.Common.ExtensionBehaviour` in your behaviour module. This module will then index those behaviours *and* all the modules that implement those behaviours at app startup.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """
  use GenServer, restart: :transient
  use Untangle
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Config
  alias Bonfire.Common.Cache
  alias Bonfire.Common.Enums

  @doc "List modules that implement a behaviour"
  @callback modules() :: any

  def find_extension_behaviours() do
    adopters_of_behaviour(__MODULE__)
    |> modules_only()

    # |> debug()
  end

  def find_adopters_of_behaviours(behaviours \\ find_extension_behaviours()) do
    apps_to_scan()
    |> apps_with_behaviour(behaviours)
  end

  def apps_to_scan() do
    pattern = Config.get([:extensions_pattern], "bonfire")

    Application.loaded_applications()
    |> Enum.map(fn
      {app, description, _} ->
        case (String.contains?(to_string(app), pattern) or
                String.contains?(to_string(description), pattern)) and
               Application.spec(app, :modules) do
          modules when is_list(modules) and modules != [] -> {app, modules}
          _ -> nil
        end
    end)
    |> Enum.reject(&is_nil/1)

    # |> debug()
  end

  @doc """
  Given a behaviour module, filters app modules to only those that implement that behaviour
  """
  def adopters_of_behaviour(behaviour \\ __MODULE__) when is_atom(behaviour) do
    # Config.get([:extensions_grouped, behaviour], [:bonfire, :bonfire_common])
    apps_to_scan()
    # |> debug()
    |> apps_with_behaviour(behaviour)
  end

  defp apps_with_behaviour(apps, behaviour) when is_list(apps) and is_atom(behaviour) do
    apps
    |> Enum.reduce(%{}, fn
      {app, modules}, acc ->
        case modules_with_behaviour(modules, behaviour) do
          modules when is_list(modules) and modules != [] ->
            Enums.deep_merge(acc, %{app => modules})

          _ ->
            acc
        end
    end)
    |> Enum.reject(&is_nil/1)

    # |> debug()
  end

  defp apps_with_behaviour(apps, behaviours) when is_list(apps) and is_list(behaviours) do
    apps
    |> Enum.reduce(%{}, fn
      {app, modules}, acc ->
        case behaviours_with_app_modules(modules, behaviours, app) do
          modules when is_list(modules) and modules != [] -> Enums.deep_merge(acc, modules)
          _ -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reject(&is_nil/1)

    # |> debug()
  end

  defp behaviours_with_app_modules(modules, behaviours, app)
       when is_list(modules) and is_list(behaviours) do
    behaviours
    |> Enum.reduce(%{}, fn
      # {app2, behaviours2}, acc -> behaviours_with_app_modules(modules, behaviours2, app2) # dunno about this clause
      behaviour, acc ->
        case modules_with_behaviour(modules, behaviour) do
          modules when is_list(modules) and modules != [] ->
            Enums.deep_merge(acc, %{behaviour => %{app => modules}})

          _ ->
            acc
        end
    end)
    |> Enum.reject(&is_nil/1)

    # |> debug()
  end

  defp modules_with_behaviour(modules, behaviour) when is_list(modules) and is_atom(behaviour) do
    # filter out any modules that do not have the `behaviour` specified
    modules
    |> Enum.filter(fn mod ->
      behaviour in (module_behaviours(mod) || [])
    end)

    # |> debug()
  end

  def module_behaviours(module \\ __MODULE__) do
    Code.ensure_loaded?(module) and
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> List.wrap()

    # |> debug()
  end

  def cached_behaviours(), do: :persistent_term.get(__MODULE__)

  def behaviours() do
    cached_behaviours()
  rescue
    _e in ArgumentError ->
      populate()
  end

  def behaviour_app_modules(behaviour, behaviours \\ nil)
  def behaviour_app_modules(behaviour, nil), do: behaviour_app_modules(behaviour, behaviours())

  def behaviour_app_modules(behaviour, behaviours) do
    behaviours[behaviour] || []
  end

  def behaviour_modules(behaviour, behaviours \\ nil) do
    behaviour_app_modules(behaviour, behaviours)
    |> modules_only()
  end

  defp modules_only(app_modules) do
    app_modules
    |> Enum.flat_map(fn {_app, modules} -> modules end)
  end

  @doc "Runs/applies a given function name on each of a list of given modules, returning a map (listing the modules with their result as value) and vice versa (listing the results as key with their calling module as value). It also caches the result on first run."
  def apply_modules_cached(modules, fun) do
    Cache.maybe_apply_cached({__MODULE__, :apply_modules}, [modules, fun])
  end

  @doc "Note: use `apply_modules_cached/2` instead, as it caches the result."
  @decorate time()
  def apply_modules(modules, fun) do
    modules
    |> Enum.flat_map(&apply_module(&1, fun))
    |> debug()
    |> Enums.filter_empty(%{})
    |> Map.new()
  end

  defp apply_module(module, fun) do
    case Utils.maybe_apply(module, fun) do
      {:error, e} ->
        warn(e, "could not find function or module `#{module}.#{fun}/0`")
        []

      ret when is_list(ret) and ret != [] ->
        [{module, ret}] ++
          Enum.map(ret, &{&1, module})

      ret when not is_nil(ret) ->
        [{module, ret}, {ret, module}]

      e ->
        warn(e, "could not find valid info with `#{module}.#{fun}/0`")
        []
    end
  end

  # GenServer callback

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with config_module data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  @doc false
  def init(_) do
    populate()
    :ignore
  end

  def populate() do
    IO.puts("Analysing the app to prepare a list of extensions and their behaviour modules...")

    {time, indexed} = :timer.tc(__MODULE__, :find_adopters_of_behaviours, [])
    # indexed = find_adopters_of_behaviours()

    IO.puts(
      "Indexed the modules from #{Enum.count(indexed)} behaviours in #{time / 1_000_000} seconds"
    )

    # IO.inspect(indexed)

    :persistent_term.put(__MODULE__, indexed)

    indexed
  end
end
