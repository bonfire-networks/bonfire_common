defmodule Bonfire.Common.DatesTimesUlidTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Common.DatesTimes

  describe "generate_ulid_if_past/1" do
    test "dates an id from any past date" do
      date = DateTime.utc_now() |> DateTime.add(-to_timeout(day: 400), :millisecond)
      assert id = DatesTimes.generate_ulid_if_past(date)

      assert DatesTimes.date_from_pointer(id) |> DateTime.truncate(:second) ==
               DateTime.truncate(date, :second)
    end

    test "gives nothing for a future date" do
      assert DatesTimes.generate_ulid_if_past(
               DateTime.utc_now()
               |> DateTime.add(to_timeout(day: 1), :millisecond)
             ) == nil
    end
  end
end
