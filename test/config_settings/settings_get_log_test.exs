defmodule Bonfire.Common.SettingsGetLogTest do
  @moduledoc """
  `Settings.get` runs many times on every page, and an instance running at `info` level formats what it logs on each call. So what a read logs must not grow with what the user has stored. It used to print the user's whole settings struct on every read, which made each read slower the longer the user's stored settings were (see plans/keyword-filters.md, "Settings.get profile").
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  import ExUnit.CaptureLog

  alias Bonfire.Common.Settings

  test "reading a setting does not log what the user has stored" do
    stored = %{
      bonfire_social: %{some_key: 1},
      activity_pub: %{mrf_keyword: %{reject: for(i <- 1..50, do: "logmarker#{i}")}}
    }

    user = %{id: "log_test_user", settings: %Bonfire.Data.Identity.Settings{json: stored}}

    log =
      capture_log([level: :info], fn ->
        assert Settings.__get__([:some_key], nil, current_user: user, otp_app: :bonfire_social) ==
                 1
      end)

    # the positive first: the read does log, at this level, and names the user's settings by id
    assert log =~ "log_test_user"

    refute log =~ "logmarker"
  end
end
