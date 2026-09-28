defmodule Bonfire.Common.SentryBeforeSendTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :backend

  # the sentry dep is `only: [:dev, :prod]` in mix.exs, so its modules are not loaded in the test env
  @moduletag :skip

  setup do
    on_exit(fn -> Sentry.Context.clear_all() end)
  end

  # the callback as configured, so this also checks the config points at it
  defp before_send(event) do
    case Sentry.Config.before_send() do
      {mod, fun} -> apply(mod, fun, [event])
      fun when is_function(fun, 1) -> fun.(event)
    end
  end

  test "strips the IPs Sentry.PlugContext records for an HTTP request" do
    conn(:get, "/feed/hashtag")
    |> Map.put(:remote_ip, {10, 0, 0, 1})
    |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.7, 10.0.0.1")
    |> Plug.Conn.put_req_header("x-real-ip", "203.0.113.7")
    |> Plug.Conn.put_req_header("accept", "text/html")
    |> Sentry.PlugContext.call([])

    event = Sentry.Event.create_event(message: "boom") |> before_send()

    assert event.request.url =~ "/feed/hashtag"
    refute Map.has_key?(event.request.env, "REMOTE_ADDR")
    refute Map.has_key?(event.request.headers, "x-forwarded-for")
    refute Map.has_key?(event.request.headers, "x-real-ip")
    assert event.request.headers["accept"] == "text/html"
    refute inspect(event) =~ "203.0.113.7"
    refute inspect(event) =~ "10.0.0.1"
  end

  test "strips the user IP Sentry.LiveViewHook records, keeping the rest of the user context" do
    Sentry.Context.set_user_context(%{id: "user_1", ip_address: "203.0.113.7"})
    Sentry.Context.set_request_context(%{url: "https://example.local/feed/hashtag"})

    event = Sentry.Event.create_event(message: "boom") |> before_send()

    assert event.user == %{id: "user_1"}
    assert event.request.url == "https://example.local/feed/hashtag"
  end
end
