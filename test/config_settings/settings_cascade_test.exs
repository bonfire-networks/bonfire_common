defmodule Bonfire.Common.SettingsCascadeTest do
  use ExUnit.Case, async: false
  use Bonfire.Common.Utils
  alias Bonfire.Common.Settings
  alias Bonfire.Common.Config

  @test_otp_app :bonfire_common
  @test_module __MODULE__.TestKey

  setup do
    original = Application.get_env(@test_otp_app, @test_module)

    on_exit(fn ->
      if original do
        Application.put_env(@test_otp_app, @test_module, original)
      else
        Application.delete_env(@test_otp_app, @test_module)
      end
    end)

    # Set up a compile-time-style config (keyword list, like `config :bonfire_common, TestKey, location: "Default City"`)
    Application.put_env(@test_otp_app, @test_module, location: "Default City")

    :ok
  end

  describe "Settings cascade fallback to Config" do
    test "returns Config value when no user context is provided" do
      result =
        Settings.__get__([@test_module, :location], nil, otp_app: @test_otp_app)

      assert result == "Default City"
    end

    test "returns Config value when user has settings but not for this key" do
      user_with_unrelated_settings = %{
        id: "test_user_cascade",
        settings: %Bonfire.Data.Identity.Settings{
          json: %{@test_otp_app => %{SomeOtherModule => %{theme: "dark"}}}
        }
      }

      result =
        Settings.__get__(
          [@test_module, :location],
          nil,
          current_user: user_with_unrelated_settings,
          otp_app: @test_otp_app
        )

      assert result == "Default City"
    end

    test "returns Config value when user has empty settings" do
      user_with_empty_settings = %{
        id: "test_user_empty",
        settings: %Bonfire.Data.Identity.Settings{json: %{}}
      }

      result =
        Settings.__get__(
          [@test_module, :location],
          nil,
          current_user: user_with_empty_settings,
          otp_app: @test_otp_app
        )

      assert result == "Default City"
    end

    test "user setting overrides Config when present" do
      user_with_location = %{
        id: "test_user_override",
        settings: %Bonfire.Data.Identity.Settings{
          json: %{@test_otp_app => %{@test_module => %{location: "User City"}}}
        }
      }

      result =
        Settings.__get__(
          [@test_module, :location],
          nil,
          current_user: user_with_location,
          otp_app: @test_otp_app
        )

      assert result == "User City"
    end

    test "returns default when key not in Config or user settings" do
      Application.delete_env(@test_otp_app, @test_module)

      user = %{
        id: "test_user_no_config",
        settings: %Bonfire.Data.Identity.Settings{json: %{}}
      }

      result =
        Settings.__get__(
          [@test_module, :location],
          "fallback_default",
          current_user: user,
          otp_app: @test_otp_app
        )

      assert result == "fallback_default"
    end
  end

  describe "Config.put/3 preserves keyword list structure" do
    test "merges map into existing keyword list instead of replacing" do
      Application.put_env(@test_otp_app, @test_module, location: "Original", color: "blue")

      Config.put(@test_module, %{size: "large"}, @test_otp_app)

      result = Application.get_env(@test_otp_app, @test_module)

      assert is_map(result) or (is_list(result) and Keyword.keyword?(result))
      assert Bonfire.Common.Enums.get_eager(result, :location, nil) == "Original"
      assert Bonfire.Common.Enums.get_eager(result, :color, nil) == "blue"
      assert Bonfire.Common.Enums.get_eager(result, :size, nil) == "large"
    end
  end
end
