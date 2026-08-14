defmodule Bonfire.Common.Extend.PurgeTest do
  @moduledoc """
  Purging is an enforcement rather than a predicate: the code goes, and so do the processes that
  were running it. Both halves are asserted on process death, since `Code.ensure_loaded?/1` would
  reload the module from disk in `:interactive` mode and pass for the wrong reason.
  """

  # not async: purging is global to the VM
  use ExUnit.Case, async: false

  alias Bonfire.Common.Extend
  alias Bonfire.Common.PurgeFixture

  describe "purge_modules/1" do
    test "kills a process that is running the purged code" do
      # precondition: without this the test would pass vacuously against a module nobody runs
      assert Code.ensure_loaded?(PurgeFixture)
      pid = spawn(PurgeFixture, :loop, [])
      ref = Process.monitor(pid)
      assert Process.alive?(pid)

      Extend.purge_modules([PurgeFixture])

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
      refute Process.alive?(pid)
    end

    test "removes the module from the export table" do
      assert Code.ensure_loaded?(PurgeFixture)
      assert function_exported?(PurgeFixture, :loop, 0)

      Extend.purge_modules([PurgeFixture])

      # function_exported?/3 never loads, unlike Code.ensure_loaded?/1
      refute function_exported?(PurgeFixture, :loop, 0)
    end

    test "kills an idle process that the code purge alone would miss" do
      # a parked gen_server holds its module as data on the heap rather than as a stack frame, so
      # :code.purge/1 leaves it running. Assert on the shape that fails, not only on the one that works
      {:ok, pid} = PurgeFixture.start()
      ref = Process.monitor(pid)
      refute :erlang.check_process_code(pid, PurgeFixture)

      Extend.purge_modules([PurgeFixture])

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end

    test "tolerates modules that were never loaded" do
      assert :ok = Extend.purge_modules([Bonfire.Common.NoSuchModule])
    end
  end

  describe "kill_processes_started_by/1" do
    test "leaves processes started by other modules alone" do
      {:ok, pid} = PurgeFixture.start()

      assert 0 = Extend.kill_processes_started_by([Bonfire.Common.NoSuchModule])
      assert Process.alive?(pid)

      assert 1 = Extend.kill_processes_started_by([PurgeFixture])
    end
  end
end
