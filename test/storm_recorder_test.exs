defmodule Bonfire.Common.StormRecorderTest do
  @moduledoc """
  The on-demand storm attribution recorder (plan: overloaded-whale.md Phase 0): starts before a load experiment, snapshots every `interval_ms` into a bounded ring, auto-stops after its window, and MUST be zero-cost when off — telemetry handlers attach on start and detach on stop.
  """
  use ExUnit.Case, async: false
  require Logger

  alias Bonfire.Common.Telemetry.StormRecorder

  @handler_id "storm-recorder"

  setup do
    on_exit(fn -> StormRecorder.stop() end)
    :ok
  end

  defp recorder_handlers do
    :telemetry.list_handlers([])
    |> Enum.filter(&(&1.id == @handler_id))
  end

  test "start attaches telemetry handlers, stop detaches them (zero cost when off)" do
    assert recorder_handlers() == []

    assert {:ok, _pid} = StormRecorder.start(minutes: 1, interval_ms: 50)
    refute recorder_handlers() == []

    StormRecorder.stop()
    assert recorder_handlers() == []
  end

  test "ticks accumulate snapshots with the expected shape, dump returns them" do
    {:ok, _pid} = StormRecorder.start(minutes: 1, interval_ms: 50)

    # let a few ticks happen
    Process.sleep(180)

    entries = StormRecorder.dump()
    assert is_list(entries)
    assert length(entries) >= 2

    for snap <- entries do
      assert %DateTime{} = snap.at
      assert is_integer(snap.run_queue)
      assert is_integer(snap.schedulers) and snap.schedulers >= 1
      assert %{total: t, processes: p, binary: b} = snap.memory
      assert is_integer(t) and is_integer(p) and is_integer(b)
      # per-class DB counters always present, even when zero
      assert Map.has_key?(snap, :db)
      # guarded externals: real data or :unavailable, never absent
      assert Map.has_key?(snap, :pg)
      assert Map.has_key?(snap, :oban)
    end
  end

  test "DB query telemetry lands in the caller's class bucket, unmarked pids in :unknown" do
    {:ok, _pid} = StormRecorder.start(minutes: 1, interval_ms: 50)

    repo_event = Bonfire.Common.Repo.config()[:telemetry_prefix] ++ [:query]
    measurements = %{queue_time: 1_000, query_time: 2_000, total_time: 3_000}
    meta = %{query: "SELECT 1"}

    # marked as :ap — the convention is Logger metadata (one call = log-line tag + pdict marker);
    # classes are NOT a fixed list, and the AP workers' existing `action:` metadata is picked up too
    Logger.metadata(caller_class: :ap, action: "publish")
    :telemetry.execute(repo_event, measurements, meta)
    Logger.metadata(caller_class: nil, action: nil)

    # unmarked → :unknown
    :telemetry.execute(repo_event, measurements, meta)

    Process.sleep(120)

    entries = StormRecorder.dump()

    total = fn class ->
      entries |> Enum.map(&(get_in(&1.db, [class, :count]) || 0)) |> Enum.sum()
    end

    assert total.(:ap) >= 1
    assert total.(:unknown) >= 1

    action_total =
      entries |> Enum.map(&(get_in(&1.actions, ["publish", :count]) || 0)) |> Enum.sum()

    assert action_total >= 1
  end

  test "auto-stops after its window and detaches handlers" do
    # tiny window: 1 tick interval, auto-stop via an explicit short window
    {:ok, pid} = StormRecorder.start(minutes: 1, interval_ms: 50, auto_stop_ms: 150)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
    assert recorder_handlers() == []
  end

  test "stop and dump when not running return an error instead of raising" do
    assert {:error, :not_running} = StormRecorder.dump()
    assert {:error, :not_running} = StormRecorder.status()
    # stop is idempotent
    assert StormRecorder.stop() in [:ok, {:error, :not_running}]
  end

  test "ring respects its bound (oldest entries dropped)" do
    # window sized to exactly 3 entries: minutes * 60_000 / interval
    {:ok, _pid} =
      StormRecorder.start(interval_ms: 50, minutes: 1, max_entries: 3)

    Process.sleep(400)

    entries = StormRecorder.dump()
    assert length(entries) <= 3
  end
end
