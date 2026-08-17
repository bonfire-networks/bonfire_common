defmodule Bonfire.Common.Telemetry.StorageTest do
  @moduledoc """
  History exists only to backfill LiveDashboard charts with points from before the page was opened.
  That is worth having during an incident and dead weight otherwise, so it ships disabled and every knob has a conservative default.

  The disabled case is the one that matters most: it is what prod runs.
  """

  # not async: attaches globally-named telemetry handlers and reads app config
  use ExUnit.Case, async: false

  alias Bonfire.Common.Telemetry.Storage

  import Telemetry.Metrics

  @event [:test_storage, :measure]

  defp emit(n), do: :telemetry.execute(@event, %{value: n}, %{})

  # a named instance of its own: the app already runs a globally-named Storage outside prod, and
  # options are passed directly rather than via app config so these stay independent of it
  defp start_storage(metrics, opts) do
    name = :"storage_#{System.unique_integer([:positive])}"
    start_supervised!({Storage, {metrics, Keyword.put(opts, :name, name)}}, id: name)
    name
  end

  test "keeps at most the configured number of points" do
    metric = last_value("test_storage.measure.value")
    server = start_storage([metric], enabled: true, history_buffer_size: 3)

    for n <- 1..10, do: emit(n)

    assert length(Storage.metrics_history(metric, server)) == 3
  end

  test "buffers nothing when disabled, which is the prod default" do
    metric = last_value("test_storage.measure.value")
    server = start_storage([metric], enabled: false)

    for n <- 1..5, do: emit(n)

    assert Storage.metrics_history(metric, server) == []
  end

  test "buffers only the metrics allowed by the filter" do
    kept = last_value("test_storage.measure.value")
    skipped = last_value("test_storage.measure.other")

    server =
      start_storage([kept, skipped],
        enabled: true,
        history_buffer_size: 10,
        metrics_filter: ["test_storage.measure.value"]
      )

    :telemetry.execute(@event, %{value: 1, other: 2}, %{})

    assert [_] = Storage.metrics_history(kept, server)
    assert Storage.metrics_history(skipped, server) == []
  end
end
