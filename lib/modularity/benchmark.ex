defmodule Bonfire.Common.Benchmark do
  @moduledoc "Simple way to measure the execution time of functions. It is preferred to use `@decorate` from `Untangle` instead."
  import Logger

  def apply_timed(function) do
    {time, result} = :timer.tc(function)

    Logger.info("#{time / 1_000} ms to run anonymous function #{inspect(function)}")

    result
  end

  def apply_timed(function, args) do
    {time, result} = :timer.tc(function, args)

    Logger.info("#{time / 1_000} ms to run #{inspect(function)}/#{length(args)}")

    result
  end

  def apply_timed(module, function, args) do
    {time, result} = :timer.tc(module, function, args)

    Logger.info("#{time / 1_000} ms to run #{module}.#{function}/#{length(args)}")

    result
  end
end
