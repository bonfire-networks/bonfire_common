defmodule Bonfire.Common.Benchmark do
  import Logger

  # TODO: make these macros (and move them to Untangle) to log with code location info and to skip the measuring depending on env
  
  def apply_timed(function) do
    
    {time, result} = :timer.tc(function)

    info("Time to run anonymous function #{inspect function}: #{time / 1_000} ms")
    
    result
  end

  def apply_timed(function, args) do
    
    {time, result} = :timer.tc(function, args)

    info("Time to run #{inspect function}/#{length(args)}: #{time / 1_000} ms")
    
    result
  end

  def apply_timed(module, function, args) do
    
    {time, result} = :timer.tc(module, function, args)

    info("Time to run #{module}.#{function}/#{length(args)}: #{time / 1_000} ms")
    
    result
  end
end