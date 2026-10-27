defmodule Bonfire.Common.DatesTimesDurationsTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.DatesTimes

  test "remove/3 takes days off a DateTime" do
    dt = ~U[2024-07-25 12:00:00Z]
    assert DatesTimes.remove(dt, 10, :day) == ~U[2024-07-15 12:00:00Z]
  end

  test "format_duration/1 shows seconds, minutes, or hours and minutes" do
    assert DatesTimes.format_duration(0.5) == "0.5s"
    assert DatesTimes.format_duration(59.99) == "59.99s"
    assert DatesTimes.format_duration(61.5) == "1min"
    assert DatesTimes.format_duration(3599.9) == "59min"
    assert DatesTimes.format_duration(3725.25) == "1h 2min"
    assert DatesTimes.format_duration(90061) == "25h 1min"
    assert DatesTimes.format_duration("61.5") == "1min"
  end
end
