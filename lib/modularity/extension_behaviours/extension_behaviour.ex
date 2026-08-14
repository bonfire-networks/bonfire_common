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
  use Bonfire.Common.Config
  alias Bonfire.Common.Cache
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Extend
  alias Bonfire.Common.ModuleAnalyzer

  @doc "List modules that implement a behaviour"
  @callback modules() :: any

  # registered by `Bonfire.Application.start/2` (as `@sup_name`), so it exists exactly while the app is running
  @app_supervisor Bonfire.Supervisor

  defp prepare_data_for_cache(opts) do
    # fist index appps
    app_modules_to_scan = ModuleAnalyzer.app_modules_to_scan(opts)
    # then find all *declared* behaviours (which are a behaviour of this module)
    app_modules_to_scan
    |> find_extension_behaviours()
    # then find modules that implement those behaviours
    |> find_adopters_of_behaviours(app_modules_to_scan)
  end

  # multiple behaviours
  def find_adopters_of_behaviours(
        behaviours \\ find_extension_behaviours(),
        app_modules_to_scan \\ ModuleAnalyzer.app_modules_to_scan()
      ) do
    app_modules_to_scan
    |> apps_with_behaviour(behaviours)
  end

  def find_extension_behaviours(app_modules_to_scan \\ ModuleAnalyzer.app_modules_to_scan()) do
    adopters_of_behaviour(__MODULE__, app_modules_to_scan)
    |> ModuleAnalyzer.modules_only()
  end

  @doc """
  Given a behaviour module, filters app modules to only those that implement that behaviour
  """
  def adopters_of_behaviour(
        behaviour \\ __MODULE__,
        app_modules_to_scan \\ ModuleAnalyzer.app_modules_to_scan()
      )
      when is_atom(behaviour) do
    app_modules_to_scan
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
  end

  defp behaviours_with_app_modules(modules, behaviours, app)
       when is_list(modules) and is_list(behaviours) do
    behaviours
    |> Enum.reduce(%{}, fn
      behaviour, acc ->
        case modules_with_behaviour(modules, behaviour) do
          modules when is_list(modules) and modules != [] ->
            Enums.deep_merge(acc, %{behaviour => %{app => modules}})

          _ ->
            acc
        end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Now using ModuleAnalyzer
  defp modules_with_behaviour(modules, behaviour) when is_list(modules) and is_atom(behaviour) do
    modules
    |> Enum.filter(fn module ->
      Extend.module_behaviour?(module, behaviour)
    end)
  end

  def cached_behaviours(), do: :persistent_term.get(__MODULE__)

  @doc """
  Returns the cached registry, rebuilding it first if the loaded applications have changed since it was cached.

  The registry reflects whatever was reachable when it was populated. Before the app starts that is incidental: `use_modules/0`-style macros expand while compiling, so a snapshot taken then is whatever the first caller happened to trip, and was then reused for the rest of the build. One prod build compiled a router from 11 route modules while the running system reported 17, silently dropping `/messages` among others — even though a scan at that point finds 21.

  Two ways it can be stale, hence two checks. Applications may have loaded since, which `apps_changed?/0` catches. Or the scan ran while `Mix.Project.in_project/4` had the code path narrowed to one dependency's own tree, which `Bonfire.Common.ModuleAnalyzer.code_path_changed?/0` catches: everything outside that tree is loaded and listed in its application spec, but cannot be loaded, so it fails every behaviour check and leaves no trace of having been missed.

  Both are skipped entirely once the app is running, where the code path and the loaded applications are settled: they cost ~1ms against 0.02µs to read the cache, on a path hit for every module lookup. While compiling it is the other way round, ~1ms against ~80ms to rescan, and buys a rescan only when something actually changed.
  """
  def behaviours() do
    if app_started?() or (not apps_changed?() and not ModuleAnalyzer.code_path_changed?()) do
      cached_behaviours()
    else
      populate(cache: true)
    end
  rescue
    _e in ArgumentError ->
      populate(cache: true)
  end

  # the app list cached by the last scan doubles as the baseline to compare against, so only one copy of it is ever kept
  defp apps_changed? do
    case Extend.cached_loaded_applications_map() do
      nil ->
        # nothing recorded to compare against, so leave it to the rescan to read the applications and record them
        true

      cached ->
        # `cache: true` records what it read, in one step moving the baseline on and priming the rescan below with the fresh list. Left stale it would serve that rescan the very list it is meant to replace, and match here forever after
        Extend.uncached_loaded_applications_map(cache: true) != cached
    end
  end

  @doc "Whether the app is running, as opposed to eg. being compiled."
  def app_started?, do: is_pid(Process.whereis(@app_supervisor))

  def behaviour_app_modules(behaviour, behaviours \\ nil)
  def behaviour_app_modules(behaviour, nil), do: behaviour_app_modules(behaviour, behaviours())

  def behaviour_app_modules(behaviour, behaviours) do
    behaviours[behaviour] || []
  end

  def behaviour_modules(behaviour, behaviours \\ nil) do
    behaviour_app_modules(behaviour, behaviours)
    |> ModuleAnalyzer.modules_only()
  end

  @doc "Runs/applies a given function name on each of a list of given modules, returning a map (listing the modules with their result as value) and vice versa (listing the results as key with their calling module as value). It also caches the result on first run."
  def apply_modules_cached(modules, fun) do
    Cache.maybe_apply_cached({__MODULE__, :apply_modules}, [modules, fun])
  end

  @doc """
  Returns the modules that `behaviour_module`'s declared modules name via `callback`.

  Used to infer one behaviour's members from the other two: a context module declaring `schema_module/0` tells us about a schema that may never declare `SchemaModule` itself.

  Only the declared list is read, never another behaviour's inferred list, which is what keeps the three `modules_inferred/0` implementations from recursing into each other.
  """
  def modules_pointed_at(behaviour_module, callback) do
    declared = behaviour_module.modules()

    linked = apply_modules_cached(declared, callback)

    # `apply_modules/2` caches both directions, so looking each declaring module up by key is what isolates the pointed-at side from the modules doing the pointing
    declared
    |> Enum.flat_map(&List.wrap(linked[&1]))
    |> Enum.filter(&is_atom/1)
    |> Enum.reject(&is_nil/1)
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

  # GenServer callbacks

  @spec start_link(ignored :: term) :: GenServer.on_start()
  @doc "Populates the global cache with behaviour data via introspection."
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  @doc false
  def init(_) do
    populate(cache: true)
    :ignore
  end

  def populate(opts \\ [cache: true]) do
    # Use the common populate_registry function
    ModuleAnalyzer.populate_registry(__MODULE__, fn -> prepare_data_for_cache(opts) end)
  end

  defdelegate apps_to_scan, to: ModuleAnalyzer
end
