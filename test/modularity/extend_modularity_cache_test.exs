defmodule Bonfire.Common.ExtendModularityCacheTest do
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.Extend
  alias Bonfire.Common.Config

  setup do
    # Clear any leftover cache entries from prior tests
    Extend.clear_modularity_cache()
    :ok
  end

  describe "maybe_module/2" do
    test "returns available module" do
      assert Extend.maybe_module(Bonfire.Common) == Bonfire.Common
    end

    test "returns nil for nil" do
      assert Extend.maybe_module(nil) == nil
    end

    test "returns nil for false" do
      assert Extend.maybe_module(false) == nil
    end

    test "returns nil when module disabled via config" do
      Config.put([DisabledTestModule, :modularity], :disabled)

      Extend.clear_modularity_cache(DisabledTestModule)
      assert Extend.maybe_module(DisabledTestModule) == nil
    after
      Config.delete([DisabledTestModule, :modularity])
      Extend.clear_modularity_cache()
    end

    test "returns replacement when module swapped via config" do
      Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Enums, :bonfire_common)

      Extend.clear_modularity_cache(Bonfire.Common.Text)
      assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Enums
    after
      Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Text, :bonfire_common)
      Extend.clear_modularity_cache()
    end
  end

  describe "clear_modularity_cache/1" do
    test "clears cache for a specific module" do
      # Prime the cache by calling maybe_module
      Extend.maybe_module(Bonfire.Common)
      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) != :not_cached

      Extend.clear_modularity_cache(Bonfire.Common)
      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) == :not_cached
    end
  end

  describe "clear_modularity_cache/0" do
    test "clears all modularity cache entries" do
      # Prime cache for multiple modules
      Extend.maybe_module(Bonfire.Common)
      Extend.maybe_module(Bonfire.Common.Text)

      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) != :not_cached
      assert Process.get({:modularity_cache, Bonfire.Common.Text}, :not_cached) != :not_cached

      Extend.clear_modularity_cache()

      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) == :not_cached
      assert Process.get({:modularity_cache, Bonfire.Common.Text}, :not_cached) == :not_cached
    end
  end

  describe "cache busting via Settings.put" do
    setup do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)
      {:ok, user: user}
    end

    test "modularity change via Settings.put resets process cache", %{user: user} do
      # Prime cache
      Extend.maybe_module(Bonfire.Common)
      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) != :not_cached

      # Change a modularity setting via Settings.put
      Bonfire.Common.Settings.put(
        [Bonfire.Common, :modularity],
        :disabled,
        current_user: user,
        scope: :instance,
        skip_boundary_check: true
      )

      # Cache for that module should be updated with the new value
      assert Process.get({:modularity_cache, Bonfire.Common}, :not_cached) == :disabled
    after
      Bonfire.Common.Settings.delete(
        [:bonfire_common, Bonfire.Common, :modularity],
        scope: :instance,
        skip_boundary_check: true
      )

      Extend.clear_modularity_cache()
    end
  end

  describe "extension_enabled?/2" do
    test "returns true for loaded extension" do
      assert Extend.extension_enabled?(:bonfire_common)
    end

    test "returns false for non-existent extension" do
      refute Extend.extension_enabled?(:non_existent_extension)
    end
  end

  describe "disabled_value?/1" do
    test "recognizes disabled values" do
      assert Extend.disabled_value?(:disabled)
      assert Extend.disabled_value?(:disable)
      assert Extend.disabled_value?({:disabled, true})
      assert Extend.disabled_value?({:disable, true})
      assert Extend.disabled_value?(disabled: true)
      assert Extend.disabled_value?(disable: true)
    end

    test "rejects non-disabled values" do
      refute Extend.disabled_value?(nil)
      refute Extend.disabled_value?(false)
      refute Extend.disabled_value?(SomeModule)
    end
  end
end
