defmodule Bonfire.Common.StartupTimer do
  @moduledoc """
  Open the console without starting the app: `iex -S mix run --no-start` or `just imix run --no-start`

  And then run `Bonfire.Common.StartupTimer.run()`
  """

  def run(application \\ :bonfire) do
    # (1)
    complete_deps = deps_list(application)

    # (2)
    dep_start_times =
      Enum.map(complete_deps, fn app ->
        case :timer.tc(fn -> Application.start(app) end) do
          {time, :ok} -> {time, app}
          # Some dependencies like :kernel may have already been started, we can ignore them
          {time, {:error, {:already_started, _}}} -> {time, app}
          # Raise an exception if we get an non-successful return value
          {_time, error} -> raise(error)
        end
      end)

    dep_start_times
    # (3)
    |> Enum.sort()
    |> Enum.reverse()
  end

  defp deps_list(app) do
    # Get all dependencies for the app
    deps = Application.spec(app, :applications)

    # Recursively call to get all sub-dependencies
    complete_deps = Enum.map(deps, fn dep -> deps_list(dep) end)

    # Build a complete list of sub dependencies, with the top level application
    # requiring them listed last, also remove any duplicates
    [complete_deps, [app]]
    |> List.flatten()
    |> Enum.uniq()
  end
end
