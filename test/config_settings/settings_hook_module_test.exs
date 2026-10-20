defmodule Bonfire.Common.SettingsHookModuleTest do
  @moduledoc """
  Modules declaring `Bonfire.Common.SettingsHookModule` process the stored value at the settings paths they name, when a setting is read.

  The hook modules below are defined in this file, which no app lists among its modules, so the registry scan can't find them: each test plants them in the behaviour registry by hand (see `behaviour_cache_invalidation_test.exs`).
  """
  use ExUnit.Case, async: false

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag that `Bonfire.Common.DataCase` applies
  @moduletag :backend

  alias Bonfire.Common.ExtensionBehaviour
  alias Bonfire.Common.Settings

  defmodule FakeHookA do
    @behaviour Bonfire.Common.SettingsHookModule

    @impl true
    def settings_hook_paths, do: [[:bonfire_common, :hook_probe]]

    @impl true
    def settings_loaded(path, value) do
      send(self(), {:hook, __MODULE__, path})
      Map.update(value, :order, [:a], &(&1 ++ [:a]))
    end
  end

  defmodule FakeHookB do
    @behaviour Bonfire.Common.SettingsHookModule

    @impl true
    def settings_hook_paths, do: [[:bonfire_common, :hook_probe]]

    @impl true
    def settings_loaded(path, value) do
      send(self(), {:hook, __MODULE__, path})
      Map.update(value, :order, [:b], &(&1 ++ [:b]))
    end
  end

  setup do
    on_exit(fn -> ExtensionBehaviour.populate() end)
    :ok
  end

  # `modules` is the order the registry lists them in
  defp register_hooks(modules) do
    others =
      ExtensionBehaviour.behaviours()
      |> Enum.reject(&match?({Bonfire.Common.SettingsHookModule, _}, &1))

    :persistent_term.put(
      ExtensionBehaviour,
      [{Bonfire.Common.SettingsHookModule, %{bonfire_common: modules}} | others]
    )
  end

  defp user_with_stored(json) do
    %{id: "hook_test_user", settings: %Bonfire.Data.Identity.Settings{json: json}}
  end

  defp read(user, otp_app, keys),
    do: Settings.__get__(keys, nil, current_user: user, otp_app: otp_app)

  describe "settings load hooks" do
    test "a hook's return value is what a read of its path gives, and the stored value stays as written" do
      register_hooks([FakeHookA])
      user = user_with_stored(%{bonfire_common: %{hook_probe: %{n: 1}}})

      assert read(user, :bonfire_common, [:hook_probe, :order]) == [:a]
      assert_received {:hook, FakeHookA, [:bonfire_common, :hook_probe]}

      # a second read starts again from the stored value: the hook's output was not written back
      assert read(user, :bonfire_common, [:hook_probe, :order]) == [:a]
      assert user.settings.json == %{bonfire_common: %{hook_probe: %{n: 1}}}
    end

    test "a read for another otp_app runs no hook" do
      register_hooks([FakeHookA])

      user =
        user_with_stored(%{
          bonfire_common: %{hook_probe: %{n: 1}},
          bonfire_social: %{hook_unrelated: 1}
        })

      # the positive first: the hook does run for its own app
      assert read(user, :bonfire_common, [:hook_probe, :order]) == [:a]
      assert_received {:hook, FakeHookA, _}

      assert read(user, :bonfire_social, [:hook_unrelated]) == 1
      refute_received {:hook, _, _}
    end

    test "several hooks on one path all run, in module-name order whatever order the registry lists them in" do
      register_hooks([FakeHookB, FakeHookA])
      user = user_with_stored(%{bonfire_common: %{hook_probe: %{n: 1}}})

      assert read(user, :bonfire_common, [:hook_probe, :order]) == [:a, :b]
    end
  end

  # Enablement is toggled at runtime (instance level), so a hook must follow it: skipped while its extension is disabled, back as soon as it is enabled, with nothing to reset in between. These use the real keyword hook of `bonfire_boundaries`.
  describe "settings load hooks and a toggled extension" do
    test "a hook table first built while its extension is disabled has the hook once it is enabled" do
      Bonfire.Common.Testing.with_extension_disabled(:bonfire_boundaries, fn ->
        Bonfire.Common.SettingsHookModule.hooks()
      end)

      assert {[:activity_pub, :mrf_keyword], Bonfire.Boundaries.BlockKeywords} in (Bonfire.Common.SettingsHookModule.hooks()[
                                                                                     :activity_pub
                                                                                   ] || [])
    end

    test "a hook does not run while its extension is disabled, and runs again once enabled" do
      user = user_with_stored(%{activity_pub: %{mrf_keyword: %{reject: ["spam"]}}})
      read = fn -> read(user, :activity_pub, [:mrf_keyword, :reject_compiled]) end

      # the positive first: the hook builds the compiled pattern while enabled
      assert {_, _} = read.()

      assert Bonfire.Common.Testing.with_extension_disabled(:bonfire_boundaries, read) == nil

      assert {_, _} = read.()
    end
  end
end
