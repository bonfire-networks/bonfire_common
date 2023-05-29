defmodule Bonfire.Common.Benchmark do
  @moduledoc "Simple way to measure the execution time of functions. It is preferred to use `@decorator` from `Untangle` instead."
  import Logger

  def apply_timed(function) do
    {time, result} = :timer.tc(function)

    IO.inspect("Time to run anonymous function #{inspect(function)}: #{time / 1_000} ms")

    result
  end

  def apply_timed(function, args) do
    {time, result} = :timer.tc(function, args)

    IO.inspect("Time to run #{inspect(function)}/#{length(args)}: #{time / 1_000} ms")

    result
  end

  def apply_timed(module, function, args) do
    {time, result} = :timer.tc(module, function, args)

    IO.inspect("Time to run #{module}.#{function}/#{length(args)}: #{time / 1_000} ms")

    result
  end
end
