# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.SettingsHookModule do
  @moduledoc """
  A global registry of modules that process a stored setting when it is read.

  A setting's meaning belongs to the extension that owns it: the compiled pattern behind a user's filtered keywords is `bonfire_boundaries`'. `Bonfire.Common.Settings` cannot name that extension, which depends on it, so each module declares the paths it processes here instead, and `Settings` asks this registry. Same reasoning as `Bonfire.Common.FeedFilterModule`.

  A hook receives the stored value at one of its paths and returns the value to use in its place. It runs on a copy of the stored data, on every read of that path's otp_app (the first element of the path), so it must be cheap: cache anything expensive, keyed by the value. Nothing a hook returns is written back to the database, so it may hold data that cannot be serialised, such as a compiled pattern.

  Several modules may declare the same path. They run in module-name order, each receiving the previous one's result.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []
  import Untangle

  @doc "The settings paths this module processes, each starting with the otp_app, eg. `[[:activity_pub, :mrf_keyword]]`"
  @callback settings_hook_paths() :: [[atom]]

  @doc "Returns the value to use in place of the `value` stored at `path` (one of the paths declared by `settings_hook_paths/0`)"
  @callback settings_loaded(path :: [atom], value :: any) :: any

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end

  @doc """
  Runs the hooks of one otp_app, or of every app when `otp_app` is `nil`, over a map of settings, and returns the processed copy.

  A read for an app with no hooks costs a lookup in the cached table (see `hooks/0`).
  """
  def apply_hooks(settings, otp_app \\ nil)

  def apply_hooks(settings, otp_app) when is_map(settings) do
    otp_app
    |> hooks_for()
    |> Enum.reduce(settings, fn {path, module}, acc ->
      case get_in(acc, path) do
        nil ->
          acc

        value ->
          # extensions are toggled at runtime, so this is checked here and not when the table is built
          if Bonfire.Common.Extend.module_enabled?(module),
            do: put_in(acc, path, module.settings_loaded(path, value)),
            else: acc
      end
    end)
  end

  def apply_hooks(settings, _otp_app), do: settings

  defp hooks_for(nil), do: hooks() |> Map.values() |> List.flatten()
  defp hooks_for(otp_app), do: hooks()[otp_app] || []

  @doc """
  The `{path, module}` pairs of every registered hook, grouped by otp_app and in the order they run.

  The paths come from `ExtensionBehaviour.apply_modules_cached/2`, which keeps what the modules declare (enabled or not) and rebuilds when the list of modules changes.
  """
  @spec hooks() :: %{atom => [{[atom], module}]}
  def hooks() do
    modules = modules()

    paths_by_module =
      Bonfire.Common.ExtensionBehaviour.apply_modules_cached(modules, :settings_hook_paths)

    modules
    |> Enum.sort()
    |> Enum.flat_map(fn module ->
      paths_by_module
      |> Map.get(module, [])
      |> Enum.flat_map(fn
        [otp_app | _] = path when is_atom(otp_app) ->
          [{path, module}]

        other ->
          warn(other, "ignoring an invalid settings hook path declared by #{inspect(module)}")
          []
      end)
    end)
    |> Enum.group_by(fn {[otp_app | _], _module} -> otp_app end)
  end
end
