defmodule Bonfire.Common.ConfigSettingsRegistryTest do
  use ExUnit.Case, async: true
  import Untangle

  alias Bonfire.Common.ConfigSettingsRegistry

  # Define test modules using actual registration mechanism
  defmodule TestConfigModule do
    use Bonfire.Common.Config

    # Define config keys with different patterns

    Config.get(:js_config, %{})

    def testing do
      Config.get(:untangle, nil)

      Config.get([:bonfire_common, :max_user_images_file_size], 5)

      Config.get([:instance, :allowed_post_formats], ["text/plain", "text/markdown", "text/html"])

      Config.get([__MODULE__, :can_reboost_after], false)
    end
  end

  defmodule AnotherTestConfigModule do
    use Bonfire.Common.Config

    # Define config keys, including a duplicate of 'untangle' to test merging
    def testing do
      Config.get(:untangle, nil)

      Config.get(:thread_default_max_depth, 3)
    end
  end

  defmodule TestSettingsModule do
    use Bonfire.Common.Settings
    use Bonfire.Common.Localise
    import TestConfigModule
    import Bonfire.Common.Utils
    import Bonfire.UI.Common
    alias Bonfire.Common.DatesTimes

    def testing do
      scope = nil
      socket = nil

      # Define settings keys with different options
      Settings.get([Bonfire.UI.Common.LogoLive, :only_logo], false,
        context: %{__context__: nil},
        scope: scope
      )

      Settings.get([:ui, :date_time_format], :relative,
        context: assigns(socket),
        name: l("Date format"),
        description: l("How to display the date/time of activities"),
        type: :select,
        options: Keyword.merge([relative: l("Relative")], DatesTimes.available_formats())
      )

      Settings.get([:ui, :theme, :instance_theme], "dark", current_user(%{}))
    end
  end

  setup_all do
    ConfigSettingsRegistry.cached_data(test_modules())
    :ok
  end

  describe "registration mechanism" do
    test "config modules should have bonfire_config_keys function" do
      assert function_exported?(TestConfigModule, :__bonfire_config_keys__, 0)
      assert function_exported?(AnotherTestConfigModule, :__bonfire_config_keys__, 0)
      assert function_exported?(TestSettingsModule, :__bonfire_config_keys__, 0)
      assert TestConfigModule.__bonfire_config_keys__() != []
    end

    test "config registration should store correct type, keys and defaults" do
      config_keys =
        TestConfigModule.__bonfire_config_keys__()
        |> debug("keys")

      # Verify all are registered as config type
      assert Enum.all?(config_keys, fn entry -> entry.type == :config end)

      # Find specific keys and verify their values

      assert files_key =
               Enum.find(config_keys, fn entry ->
                 entry.keys == [:bonfire_common, :max_user_images_file_size]
               end)

      assert files_key.default == 5

      assert formats_key =
               Enum.find(config_keys, fn entry ->
                 entry.keys == [:instance, :allowed_post_formats]
               end)

      assert formats_key.default == ["text/plain", "text/markdown", "text/html"]
    end

    @tag :todo
    test "config registration should support config apply at compile-time" do
      config_keys =
        TestConfigModule.__bonfire_config_keys__()
        |> debug("keys")

      assert verbs_key = Enum.find(config_keys, fn entry -> entry.keys == :js_config end)
      assert verbs_key.default == nil
    end

    test "settings registration should store correct type, keys, defaults and opts" do
      settings_keys =
        TestSettingsModule.__bonfire_config_keys__()
        |> debug("keys")

      # Verify all are registered as settings type
      assert Enum.all?(settings_keys, fn entry -> entry.type == :settings end)

      # Check specific settings key
      assert date_format_key =
               Enum.find(settings_keys, fn entry ->
                 entry.keys == [:ui, :date_time_format]
               end)

      assert date_format_key.default == :relative
      assert {:l, _, ["Date format"]} = Keyword.get(date_format_key.opts, :name)
      assert Keyword.get(date_format_key.opts, :type) == :select

      # Check options AST is preserved
      assert options = Keyword.get(date_format_key.opts, :options)
      assert is_tuple(options)
    end
  end

  describe "registry initialization" do
    test "cached_data builds the registry" do
      # Get the cached data
      data = ConfigSettingsRegistry.cached_data()

      assert is_map(data)
      assert Map.has_key?(data, :config)
      assert Map.has_key?(data, :settings)
    end
  end

  describe "config keys" do
    test "config_keys returns all config keys used at runtime" do
      config_keys =
        ConfigSettingsRegistry.config()
        |> debug("keys")

      assert is_map(config_keys)
      assert Map.has_key?(config_keys, [:bonfire_common, :max_user_images_file_size])
      assert Map.has_key?(config_keys, [:instance, :allowed_post_formats])
      assert Map.has_key?(config_keys, [TestConfigModule, :can_reboost_after])
      assert Map.has_key?(config_keys, :untangle)
      assert Map.has_key?(config_keys, :thread_default_max_depth)
    end

    @tag :todo
    test "config_keys returns all config keys used at compile-time" do
      config_keys =
        ConfigSettingsRegistry.config()
        |> debug("keys")

      assert is_map(config_keys)
      assert Map.has_key?(config_keys, :js_config)
    end

    test "verbs key has merged data from two modules" do
      config_keys =
        ConfigSettingsRegistry.config()
        |> debug("keys")

      assert verbs_data = config_keys[:untangle]

      assert length(verbs_data.locations) == 2

      module_names = Enum.map(verbs_data.locations, & &1.module)
      assert TestConfigModule in module_names
      assert AnotherTestConfigModule in module_names
    end

    test "all_keys returns combined config and settings keys" do
      all_keys =
        ConfigSettingsRegistry.all()
        |> debug("keys")

      assert is_map(all_keys)
      assert Map.has_key?(all_keys, :config)
      assert Map.has_key?(all_keys, :settings)

      assert is_map(all_keys.config)
      assert is_map(all_keys.settings)
    end

    test "format_registry returns formatted registry data" do
      formatted =
        ConfigSettingsRegistry.format_registry()
        |> debug("formatted")

      assert is_map(formatted)
      assert Map.has_key?(formatted, :config)
      assert Map.has_key?(formatted, :settings)

      assert is_list(formatted.config)
      assert is_list(formatted.settings)

      # Check that the first config entry has the expected format
      config_entry = List.first(formatted.config)
      assert is_map(config_entry)
      assert Map.has_key?(config_entry, :keys)
      assert Map.has_key?(config_entry, :default)
      assert Map.has_key?(config_entry, :locations)
    end
  end

  describe "settings keys" do
    test "settings_keys returns all settings keys" do
      settings_keys =
        ConfigSettingsRegistry.settings()
        |> debug("keys")

      assert is_map(settings_keys)
      assert Map.has_key?(settings_keys, [Bonfire.UI.Common.LogoLive, :only_logo])
      assert Map.has_key?(settings_keys, [:ui, :date_time_format])
      assert Map.has_key?(settings_keys, [:ui, :theme, :instance_theme])
    end

    test "settings keys contain the right metadata" do
      settings_keys =
        ConfigSettingsRegistry.settings()
        |> debug("keys")

      assert date_format = settings_keys[[:ui, :date_time_format]]

      # Check default is evaluated
      assert date_format.default == :relative
      assert "Date format" = Keyword.get(date_format.opts, :name)
      assert Keyword.get(date_format.opts, :type) == :select

      # Check options are preserved + evaluated
      assert options = Keyword.get(date_format.opts, :options)
      assert is_list(options)
      assert Keyword.get(options, :relative) == "Relative"
      assert Keyword.get(options, :long) == "Long"
    end
  end

  # Function to expose test modules to the mock
  def test_modules do
    [
      {
        :test_app,
        [
          TestConfigModule,
          AnotherTestConfigModule,
          TestSettingsModule
        ]
      }
    ]
  end
end
