defmodule Bonfire.Common.PurgeFixture do
  @moduledoc """
  A stand-in module to purge, so tests never have to purge real code and wreck the rest of the run.

  Two shapes, because the two halves of a purge catch different processes:

  `loop/0` blocks in a `receive` *inside this module*, so the process has this module's code on its call stack, which is precisely the condition under which `:code.purge/1` terminates it.

  `start/0` starts an idle `GenServer`, parked in `:gen_server.loop/7` with this module held as data rather than as a stack frame, so `:code.purge/1` does *not* touch it. Only `Bonfire.Common.Extend.kill_processes_started_by/1` ends that one.

  Deliberately unlinked: a `:kill` propagates down links, so linking it to the test process would take the test down with it.
  """

  use GenServer

  def loop do
    receive do
      :stop -> :ok
      _ -> loop()
    end
  end

  def start, do: GenServer.start(__MODULE__, :ok)

  @impl GenServer
  def init(:ok), do: {:ok, :ok}
end
