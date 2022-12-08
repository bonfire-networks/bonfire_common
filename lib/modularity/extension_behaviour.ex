# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ExtensionBehaviour do
  @moduledoc """
  A Global cache of known Behaviours in Bonfire

  Use of the ExtensionBehaviour Service requires ddding `@behaviour Bonfire.Common.ExtensionBehaviour` in your behaviour modules. This modules when then index those behaviours *and* all the modules that implement those behaviours at startup.

  While this module is a GenServer, it is only responsible for setup
  of the cache and then exits with :ignore having done so. It is not
  recommended to restart the service as this will lead to a stop the
  world garbage collection of all processes and the copying of the
  entire cache to each process that has queried it since its last
  local garbage collection.
  """
  use GenServer, restart: :transient
  import Untangle
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Config

  @doc "List modules that implement a behaviour"
  @callback modules() :: any

  defp find_behaviours() do
    adopters_of_behaviour(__MODULE__)
    |> modules_only()

    # |> debug()
  end

  def find_adopters_of_behaviours(behaviours \\ find_behaviours()) do
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
  defp adopters_of_behaviour(behaviour) when is_atom(behaviour) do
    Config.get([:extensions_grouped, behaviour], [:bonfire, :bonfire_common])
    # |> debug()
    |> apps_with_behaviour(behaviour)
  end

  defp apps_with_behaviour(apps, behaviour) when is_list(apps) and is_atom(behaviour) do
    apps
    |> Enum.reduce(%{}, fn
      app, acc ->
        case modules_with_behaviour(Application.spec(app, :modules) || [], behaviour) do
          modules when is_list(modules) and modules != [] ->
            Utils.deep_merge(acc, %{app => modules})

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
          modules when is_list(modules) and modules != [] -> Utils.deep_merge(acc, modules)
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
            Utils.deep_merge(acc, %{behaviour => %{app => modules}})

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

  def module_behaviours(module) do
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
    e in ArgumentError ->
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

  defp modules_only(app_modules \\ nil) do
    app_modules
    |> Enum.flat_map(fn {_app, modules} -> modules end)
  end

  def linked_modules(modules, fun) do
    modules
    |> Enum.flat_map(&linked_module(&1, fun))
    |> Utils.filter_empty([])
  end

  defp linked_module(module, fun) do
    case Utils.maybe_apply(module, fun) do
      linked_module when is_atom(linked_module) and not is_nil(linked_module) ->
        [{module, linked_module}, {linked_module, module}]

      _ ->
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
    IO.puts("Gathering a list of behaviour modules...")

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
