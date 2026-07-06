defmodule Bonfire.Common.OverloadTest do
  # async: false — persistent_term + named process + telemetry handlers
  use ExUnit.Case, async: false

  alias Bonfire.Common.Overload

  # drive the sampler with injected run-queue values: tests mutate the Agent, tick manually
  defp start!(opts \\ []) do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    pid =
      start_supervised!({Overload,
       Keyword.merge(
         [
           # own name: the app tree already runs a `Bonfire.Common.Overload` (in :off mode in
           # test env, it publishes once at init and never ticks, so no state contention)
           name: :overload_test_sampler,
           interval_ms: :manual,
           sample_fun: fn -> %{run_queue: Agent.get(agent, & &1)} end,
           # threshold config injected so tests don't depend on the machine's cores
           config: [
             run_queue_soft: 8,
             run_queue_hard: 20,
             up_ticks: 3,
             down_ticks: 4,
             cooldown_ms: 0,
             retry_base_s: 30,
             retry_max_s: 180,
             mode: :enforce
           ]
         ],
         opts
       )})

    %{agent: agent, pid: pid}
  end

  defp set_runq(%{agent: agent}, value), do: Agent.update(agent, fn _ -> value end)

  defp tick(%{pid: pid}, times \\ 1) do
    for _ <- 1..times do
      send(pid, :tick)
      # synchronize: the state read forces the :tick to have been processed
      :sys.get_state(pid)
    end
  end

  setup do
    on_exit(fn -> :persistent_term.erase({Overload, :state}) end)
    :ok
  end

  test "starts :ok and a single spike does not escalate" do
    ctx = start!()
    assert Overload.level() == :ok

    set_runq(ctx, 100)
    tick(ctx, 2)
    assert Overload.level() == :ok

    # a clear tick resets the streak — 2 more elevated ticks still don't trip
    set_runq(ctx, 0)
    tick(ctx)
    set_runq(ctx, 100)
    tick(ctx, 2)
    assert Overload.level() == :ok
  end

  test "sustained soft-exceeding escalates to :soft at exactly up_ticks, hard to :hard" do
    ctx = start!()

    set_runq(ctx, 10)
    tick(ctx, 3)
    assert Overload.level() == :soft

    set_runq(ctx, 50)
    tick(ctx, 3)
    assert Overload.level() == :hard
  end

  test "de-escalates ONE level after down_ticks clear ticks (hard → soft → ok)" do
    ctx = start!()
    set_runq(ctx, 50)
    tick(ctx, 3)
    assert Overload.level() == :hard

    # hovering between soft and hard: clear-for-hard, still elevated-for-soft
    set_runq(ctx, 10)
    tick(ctx, 4)
    assert Overload.level() == :soft

    set_runq(ctx, 0)
    tick(ctx, 4)
    assert Overload.level() == :ok
  end

  test "severity + retry_after scale with how far past hard the signal is" do
    ctx = start!()
    set_runq(ctx, 20)
    tick(ctx, 3)
    base = Overload.retry_after()
    assert base >= 30

    set_runq(ctx, 60)
    tick(ctx, 1)
    assert Overload.retry_after() > base
    assert Overload.retry_after() <= 180
  end

  test ":monitor mode computes levels but consumers read :ok" do
    ctx =
      start!(
        config: [
          run_queue_soft: 8,
          run_queue_hard: 20,
          up_ticks: 3,
          down_ticks: 4,
          cooldown_ms: 0,
          retry_base_s: 30,
          retry_max_s: 180,
          mode: :monitor
        ]
      )

    set_runq(ctx, 50)
    tick(ctx, 3)

    assert Overload.level() == :ok
    assert Overload.raw_level() == :hard
  end

  test "stand_down forces :ok with auto-expiry" do
    ctx = start!()
    set_runq(ctx, 50)
    tick(ctx, 3)
    assert Overload.level() == :hard

    Overload.stand_down(ctx.pid, 60_000)
    assert Overload.level() == :ok
    assert Overload.raw_level() == :hard

    # expiry restores enforcement
    Overload.stand_down(ctx.pid, 0)
    tick(ctx)
    assert Overload.level() == :hard
  end

  test "transitions emit telemetry and each tick emits a sample event" do
    ctx = start!()
    test_pid = self()

    :telemetry.attach_many(
      "overload-test",
      [[:bonfire, :overload, :sample], [:bonfire, :overload, :transition]],
      fn event, measurements, metadata, _ -> send(test_pid, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("overload-test") end)

    set_runq(ctx, 10)
    tick(ctx, 3)

    assert_received {[:bonfire, :overload, :sample], %{run_queue: 10}, _}

    assert_received {[:bonfire, :overload, :transition], _,
                     %{from: :ok, to: :soft, signal: :run_queue}}
  end

  test "shed/2 emits the shed telemetry event with the traffic class" do
    _ctx = start!()
    test_pid = self()

    :telemetry.attach(
      "overload-shed-test",
      [:bonfire, :overload, :shed],
      fn event, _m, metadata, _ -> send(test_pid, {event, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("overload-shed-test") end)

    Overload.shed(:federation, :ap_plug)
    assert_received {[:bonfire, :overload, :shed], %{class: :federation, consumer: :ap_plug}}
  end

  test "re-broadcasts an :overload_notice each elevated tick (drives the banner), none when calm" do
    ctx = start!()
    Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, "bonfire:overload")

    tick(ctx, 2)
    refute_received {:overload_notice, _}

    set_runq(ctx, 10)
    tick(ctx, 4)

    # elevated from tick 3 → notices on ticks 3 and 4
    assert_received {:overload_notice, %{level: :soft}}
    assert_received {:overload_notice, %{level: :soft}}
  end

  test "pressure/0 exposes the latest sample for the recorder" do
    ctx = start!()
    set_runq(ctx, 7)
    tick(ctx)

    assert %{run_queue: 7} = Overload.pressure()
  end
end
