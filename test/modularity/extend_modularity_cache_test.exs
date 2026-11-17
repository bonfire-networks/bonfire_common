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

    for value <- [:disabled, :disable, false, {:disabled, true}, [disabled: true]] do
      test "returns nil when module disabled via config (#{inspect(value)})" do
        Config.put(
          [Bonfire.Common.Text, :modularity],
          unquote(Macro.escape(value)),
          :bonfire_common
        )

        Extend.clear_modularity_cache(Bonfire.Common.Text)
        assert Extend.maybe_module(Bonfire.Common.Text) == nil
      after
        Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Text, :bonfire_common)
        Extend.clear_modularity_cache()
      end
    end

    test "returns replacement when module swapped via config" do
      Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Enums, :bonfire_common)

      Extend.clear_modularity_cache(Bonfire.Common.Text)
      assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Enums
    after
      Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Text, :bonfire_common)
      Extend.clear_modularity_cache()
    end

    for value <- [:enabled, :enable, true, {:enabled, true}, {:enable, true}, [enabled: true]] do
      test "returns the module itself when explicitly enabled via config (#{inspect(value)})" do
        Config.put(
          [Bonfire.Common.Text, :modularity],
          unquote(Macro.escape(value)),
          :bonfire_common
        )

        Extend.clear_modularity_cache(Bonfire.Common.Text)
        assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Text
      after
        Config.put([Bonfire.Common.Text, :modularity], Bonfire.Common.Text, :bonfire_common)
        Extend.clear_modularity_cache()
      end
    end
  end

  describe "enabled_value?/1" do
    test "recognizes enabled values" do
      assert Extend.enabled_value?(:enabled)
      assert Extend.enabled_value?(:enable)
      assert Extend.enabled_value?(true)
      assert Extend.enabled_value?({:enabled, true})
      assert Extend.enabled_value?({:enable, true})
      assert Extend.enabled_value?(enabled: true)
      assert Extend.enabled_value?(enable: true)
    end

    test "rejects non-enabled values" do
      refute Extend.enabled_value?(nil)
      refute Extend.enabled_value?(false)
      refute Extend.enabled_value?(:disabled)
      # a swapped-in module is not a plain "enabled" flag
      refute Extend.enabled_value?(SomeModule)
    end
  end

  # the cache holds one entry per scope, so look for any of them
  defp cached?(module_or_extension) do
    Enum.any?(Process.get_keys(), &match?({:modularity_cache, ^module_or_extension, _}, &1))
  end

  describe "clear_modularity_cache/1" do
    test "clears cache for a specific module" do
      # Prime the cache by calling maybe_module
      Extend.maybe_module(Bonfire.Common)
      Extend.maybe_module(Bonfire.Common.Text)
      assert cached?(Bonfire.Common)

      Extend.clear_modularity_cache(Bonfire.Common)
      refute cached?(Bonfire.Common)
      assert cached?(Bonfire.Common.Text)
    end
  end

  describe "clear_modularity_cache/0" do
    test "clears all modularity cache entries" do
      # Prime cache for multiple modules
      Extend.maybe_module(Bonfire.Common)
      Extend.maybe_module(Bonfire.Common.Text)

      assert cached?(Bonfire.Common)
      assert cached?(Bonfire.Common.Text)

      Extend.clear_modularity_cache()

      refute cached?(Bonfire.Common)
      refute cached?(Bonfire.Common.Text)
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
      assert cached?(Bonfire.Common)

      # Change a modularity setting via Settings.put
      Bonfire.Common.Settings.put(
        [Bonfire.Common, :modularity],
        :disabled,
        current_user: user,
        scope: :instance,
        skip_boundary_check: true
      )

      # Cache for that module is cleared, so the next lookup reads the new value in its own scope
      refute cached?(Bonfire.Common)
    after
      Bonfire.Common.Settings.delete(
        [:bonfire_common, Bonfire.Common, :modularity],
        scope: :instance,
        skip_boundary_check: true
      )

      Extend.clear_modularity_cache()
    end
  end

  describe "user-scoped modularity and the process cache" do
    setup do
      account = Bonfire.Me.Fake.fake_account!()

      disabler =
        Bonfire.Common.Utils.current_user(
          Bonfire.Common.Settings.put([Bonfire.Common.Text, :modularity], :disabled,
            current_user: Bonfire.Me.Fake.fake_user!(account)
          )
        )

      other = Bonfire.Me.Fake.fake_user!(account)
      {:ok, disabler: disabler, other: other}
    end

    test "a lookup without a user does not hide the user's disable", %{disabler: disabler} do
      Extend.clear_modularity_cache()

      assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Text
      assert Extend.maybe_module(Bonfire.Common.Text, current_user: disabler) == nil
    after
      Extend.clear_modularity_cache()
    end

    test "one user's disable does not leak to another user", %{
      disabler: disabler,
      other: other
    } do
      Extend.clear_modularity_cache()

      assert Extend.maybe_module(Bonfire.Common.Text, current_user: disabler) == nil
      assert Extend.maybe_module(Bonfire.Common.Text, current_user: other) == Bonfire.Common.Text
    after
      Extend.clear_modularity_cache()
    end

    test "a user-scoped put does not leak into lookups without a user", %{other: other} do
      Bonfire.Common.Settings.put([Bonfire.Common.Text, :modularity], :disabled,
        current_user: other
      )

      assert Extend.maybe_module(Bonfire.Common.Text) == Bonfire.Common.Text
    after
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
      assert Extend.disabled_value?(false)
      assert Extend.disabled_value?({:disabled, true})
      assert Extend.disabled_value?({:disable, true})
      assert Extend.disabled_value?(disabled: true)
      assert Extend.disabled_value?(disable: true)
    end

    test "rejects non-disabled values" do
      refute Extend.disabled_value?(nil)
      refute Extend.disabled_value?(true)
      refute Extend.disabled_value?(SomeModule)
    end
  end
end
