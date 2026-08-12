defmodule Bonfire.Common.BehaviourCacheInvalidationTest do
  @moduledoc """
  The behaviour registry is a `persistent_term` populated on first access from the loaded applications. At compile time that is whatever the first caller happens to trip, and the snapshot was then reused for the rest of the build, so a macro expanding early baked in a partial list.

  That is not hypothetical: `RoutesModule.use_modules/0` is a macro, and a prod build compiled a router with 11 route modules while the runtime registry held 17, silently dropping `/messages`, `/polls` and four others. A scan at that same point finds 21, so everything needed was loaded — only the cache was stale.

  Hence the cache is only trusted once the app is running. These tests plant cache entries and briefly unregister the app supervisor rather than loading and unloading real applications, which would be far more disruptive.
  """
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.ExtensionBehaviour
  alias Bonfire.Common.Extend

  @behaviours_key ExtensionBehaviour
  # as declared in `extend.ex`
  @loaded_apps_key {Extend, :loaded_apps}
  @loaded_apps_names_key {Extend, :loaded_app_names}

  @frozen_apps %{only_this: {~c"0", ~c""}}

  # `prepare_data_for_cache/0` builds a map but ends on `Enum.reject/2`, so what actually gets
  # cached is a list of tuples, only ever read through `Access`. Hence `Enum.count/1` below.
  @stale_registry []

  setup do
    # every test here corrupts global state on purpose
    on_exit(fn ->
      :persistent_term.erase(@loaded_apps_key)
      :persistent_term.erase(@loaded_apps_names_key)
      ExtensionBehaviour.populate()
    end)

    :ok
  end

  # the supervisor is how `app_started?/0` tells a running app from a compiling one
  defp as_if_not_started(fun) do
    pid = Process.whereis(Bonfire.Supervisor)
    Process.unregister(Bonfire.Supervisor)

    try do
      fun.()
    after
      Process.register(pid, Bonfire.Supervisor)
    end
  end

  describe "behaviour registry cache" do
    test "is rebuilt while not started, once applications have loaded since it was cached" do
      assert Enum.count(ExtensionBehaviour.behaviours()) > 0,
             "precondition: registry is populated"

      # a snapshot from a moment when little was loaded, exactly what a macro expanding early sees
      :persistent_term.put(@behaviours_key, @stale_registry)
      :persistent_term.put(@loaded_apps_key, @frozen_apps)

      as_if_not_started(fn ->
        assert Enum.count(ExtensionBehaviour.behaviours()) > 0,
               "a snapshot taken mid-build must be replaced, not served for the rest of the build"
      end)
    end

    test "is reused while not started when no applications have loaded since" do
      # otherwise a build would rescan on every single call, at ~80ms each
      ExtensionBehaviour.populate(cache: true)
      sentinel = [{__MODULE__, %{bonfire_common: [SomeModule]}}]
      :persistent_term.put(@behaviours_key, sentinel)

      as_if_not_started(fn -> assert ExtensionBehaviour.behaviours() == sentinel end)
    end

    test "is trusted once the app is started, without even checking the app set" do
      # that check costs ~1ms, which this path cannot afford: it is hit for every module lookup
      sentinel = [{__MODULE__, %{bonfire_common: [SomeModule]}}]
      :persistent_term.put(@behaviours_key, sentinel)
      :persistent_term.put(@loaded_apps_key, @frozen_apps)

      assert ExtensionBehaviour.app_started?(), "precondition: the app is running under test"
      assert ExtensionBehaviour.behaviours() == sentinel
    end

    test "populates when nothing is cached at all" do
      :persistent_term.erase(@behaviours_key)

      assert Enum.count(ExtensionBehaviour.behaviours()) > 0
    end

    test "rebuilding while not started refreshes the app baseline it compares against" do
      # left stale, the comparison would keep matching the same frozen list and never rebuild again,
      # since `loaded_applications_map/1` serves that key once set, whatever opt it is passed
      :persistent_term.put(@behaviours_key, @stale_registry)
      :persistent_term.put(@loaded_apps_key, @frozen_apps)

      as_if_not_started(fn -> ExtensionBehaviour.behaviours() end)

      assert Map.has_key?(Extend.loaded_applications_map(), :bonfire_common)
    end
  end

  describe "loaded app cache" do
    test "reads live and writes nothing by default" do
      :persistent_term.erase(@loaded_apps_key)

      assert Map.has_key?(Extend.loaded_applications_map(), :bonfire_common)

      assert :persistent_term.get(@loaded_apps_key, nil) == nil,
             "the default arg must leave the list live"
    end

    test "reads live and writes nothing with cache: false" do
      :persistent_term.erase(@loaded_apps_key)

      assert Map.has_key?(Extend.loaded_applications_map(cache: false), :bonfire_common)
      assert :persistent_term.get(@loaded_apps_key, nil) == nil
    end

    test "cache: true freezes the list, and the names map with it" do
      :persistent_term.erase(@loaded_apps_key)
      :persistent_term.erase(@loaded_apps_names_key)

      live = Extend.loaded_applications_map(cache: true)

      assert :persistent_term.get(@loaded_apps_key, nil) == live
      assert :persistent_term.get(@loaded_apps_names_key, nil)[:bonfire_common] == true
    end

    test "is served regardless of the cache opt once the key is set" do
      # `loaded_applications_map/1` reads the term first and `cache:` only ever controls *writing*,
      # so one `cache: true` anywhere makes the list stale for everyone, opt or no opt
      :persistent_term.put(@loaded_apps_key, @frozen_apps)

      assert Extend.loaded_applications_map() == @frozen_apps
      assert Extend.loaded_applications_map(cache: false) == @frozen_apps
      assert Extend.loaded_applications_map(cache: true) == @frozen_apps
    end

    test "invalidate_loaded_applications/0 makes it live again" do
      :persistent_term.put(@loaded_apps_key, @frozen_apps)
      :persistent_term.put(@loaded_apps_names_key, %{only_this: true})

      Extend.invalidate_loaded_applications()

      assert Map.has_key?(Extend.loaded_applications_map(), :bonfire_common)

      # only checked for membership, as `application_loaded?/1` does: uncached this falls through to
      # the full map, so the values are names only while the cache is warm
      assert Map.has_key?(Extend.loaded_applications_names(), :bonfire_common)
    end
  end

  describe "the symptom it exists to prevent" do
    test "route modules resolve through the registry" do
      modules = ExtensionBehaviour.behaviour_modules(Bonfire.UI.Common.RoutesModule)

      # if a stale snapshot is served, these drop out and their routes never reach the router
      assert Bonfire.UI.Messages.Routes in modules
      assert length(modules) > 11, "a prod build baked in 11 and lost /messages"
    end
  end
end
