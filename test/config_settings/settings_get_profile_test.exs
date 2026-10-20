defmodule Bonfire.Common.SettingsGetProfileTest do
  @moduledoc """
  Why does a `Settings.get` for a key that has nothing to do with a user's stored keywords get slower as that list grows (about 320 µs with 0 keywords and 590 µs with 200, in plans/keyword-filters.md)?

  This reads the same unset key for a user with 0 and with 200 stored keywords, times it at the test log level and with logging off, then profiles one case with `:eprof` to show where the time goes. The users are built by hand, as in `settings_cascade_test.exs`, so no database is involved.

  Excluded from the normal suite (`@moduletag :benchmark`).

  Run: `just test extensions/bonfire_common/test/config_settings/settings_get_profile_test.exs --only benchmark`
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend
  @moduletag :benchmark
  @moduletag timeout: :infinity

  alias Bonfire.Common.Settings

  @calls 300
  @profiled_calls 30

  defp user(count) do
    stored =
      if count == 0 do
        %{bonfire_social: %{some_key: 1}}
      else
        %{
          bonfire_social: %{some_key: 1},
          activity_pub: %{mrf_keyword: %{reject: for(i <- 1..count, do: "blockedword#{i}")}}
        }
      end

    %{id: "profile_user_#{count}", settings: %Bonfire.Data.Identity.Settings{json: stored}}
  end

  defp read(user),
    do: Settings.__get__([:bench_unset_key], nil, current_user: user, otp_app: :bonfire_social)

  defp micros_per_call(user) do
    for _ <- 1..20, do: read(user)
    {us, _} = :timer.tc(fn -> for _ <- 1..@calls, do: read(user) end)
    us / @calls
  end

  defp with_logging_off(fun) do
    level = Logger.level()
    Logger.configure(level: :warning)

    try do
      fun.()
    after
      Logger.configure(level: level)
    end
  end

  defp profile(user) do
    :eprof.start()
    :eprof.start_profiling([self()])
    for _ <- 1..@profiled_calls, do: read(user)
    :eprof.stop_profiling()

    out = ExUnit.CaptureIO.capture_io(fn -> :eprof.analyze(:total, sort: :time) end)
    :eprof.stop()

    # the heaviest functions are the last lines of the table
    out |> String.split("\n", trim: true) |> Enum.take(-14) |> Enum.join("\n")
  end

  @tag :benchmark
  test "Settings.get for an unrelated key: cost with 0 and 200 stored keywords, logging on and off, and where the time goes" do
    users = %{0 => user(0), 200 => user(200)}

    # the read resolves to the default for an unset key, with either user
    assert read(users[0]) == nil
    assert read(users[200]) == nil

    IO.puts("\n=== Settings.get, µs per call (#{@calls} calls each) ===")

    for {label, wrap} <- [
          {"test log level #{inspect(Logger.level())}", fn fun -> fun.() end},
          {"logging off (:warning)", &with_logging_off/1}
        ],
        count <- [0, 200] do
      us = wrap.(fn -> micros_per_call(users[count]) end)
      IO.puts("#{label}, #{count} keywords: #{Float.round(us, 1)} µs")
    end

    for count <- [0, 200] do
      IO.puts(
        "\n=== :eprof, #{count} keywords, test log level, #{@profiled_calls} calls (last lines = heaviest) ==="
      )

      IO.puts(profile(users[count]))
    end
  end
end
