defmodule Bonfire.Common.Benchmark do
  import Logger

  # FYI: use @decorator from Untangle instead

  def apply_timed(function) do
    {time, result} = :timer.tc(function)

    info("Time to run anonymous function #{inspect(function)}: #{time / 1_000} ms")

    result
  end

  def apply_timed(function, args) do
    {time, result} = :timer.tc(function, args)

    info("Time to run #{inspect(function)}/#{length(args)}: #{time / 1_000} ms")

    result
  end

  def apply_timed(module, function, args) do
    {time, result} = :timer.tc(module, function, args)

    info("Time to run #{module}.#{function}/#{length(args)}: #{time / 1_000} ms")

    result
  end
end
