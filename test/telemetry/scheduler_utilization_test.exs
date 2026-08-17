defmodule Bonfire.Common.Telemetry.SchedulerUtilizationTest do
  @moduledoc """
  Scheduler utilisation is the BEAM's honest CPU% — the fraction of wall time schedulers spent working. `:erlang.statistics(:scheduler_wall_time)` is cumulative, so a percentage needs two samples, and the first call after boot has nothing to compare against.

  The value itself is not asserted: it depends on whatever else the machine is doing, so pinning a number would be flaky. The shape and the bounds are what matter.
  """

  # not async: toggles the :scheduler_wall_time system flag, which is global
  use ExUnit.Case, async: false

  alias Bonfire.Common.Telemetry.Metrics

  setup do
    ref = make_ref()
    handler_id = {__MODULE__, ref}
    test = self()

    :telemetry.attach(
      handler_id,
      [:vm, :cpu],
      fn _event, measurements, _meta, _config -> send(test, {ref, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, ref: ref}
  end

  describe "scheduler_percentages/2" do
    # `:erlang.statistics(:scheduler_wall_time)` covers normal AND dirty-CPU schedulers, and dirty
    # ones idle almost always. Averaging across all of them halves the reported figure, so `normal`
    # has to be measured on its own or the metric silently under-reports by ~2x.
    setup do
      normal = :erlang.system_info(:schedulers_online)

      # normal schedulers half busy, dirty ones completely idle, over the same wall time
      before = for id <- 1..(normal * 2), do: {id, 0, 0}
      now = for id <- 1..(normal * 2), do: {id, if(id <= normal, do: 500, else: 0), 1000}

      {:ok, before: before, now: now}
    end

    test "reports normal schedulers without dirty ones dragging it down", ctx do
      assert %{normal: normal} = Metrics.scheduler_percentages(ctx.before, ctx.now)
      assert_in_delta normal, 50.0, 0.1
    end

    test "still reports the diluted figure separately, and the dirty schedulers' own", ctx do
      assert %{total: total, dirty_cpu: dirty} =
               Metrics.scheduler_percentages(ctx.before, ctx.now)

      # the number the metric used to report: half of the truth
      assert_in_delta total, 25.0, 0.1
      assert_in_delta dirty, 0.0, 0.1
    end
  end

  test "emits nothing on the first call, having no earlier sample to diff against", %{ref: ref} do
    Metrics.scheduler_utilization()

    refute_receive {^ref, _}, 200
  end

  test "emits a utilisation percentage once it has two samples", %{ref: ref} do
    Metrics.scheduler_utilization()
    # give the schedulers something to have been doing, so the window is not empty
    Enum.each(1..50_000, fn _ -> :erlang.phash2(0) end)
    Metrics.scheduler_utilization()

    assert_receive {^ref, measurements}, 200

    assert is_float(measurements.total)
    assert measurements.total >= 0.0 and measurements.total <= 100.0
  end
end
