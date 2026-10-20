defmodule Bonfire.Common.ApplyModulesCachedBenchmarkTest do
  @moduledoc """
  Cost of the registry lookups on hot paths: `ExtensionBehaviour.apply_modules_cached/2` (used by every `ContextModule`/`QueryModule`/`SchemaModule` lookup, so by `Needles.query/3`), `Extend.module_enabled?/2` (checked per lookup by the callers that re-check enablement), and `SettingsHookModule.apply_hooks/2` (run per `Settings.get`).

  Excluded from the normal suite (`@moduletag :benchmark`).

  Benchee runs each scenario's function repeatedly in one process, so `module_enabled?` is measured with its per-process cache warm, as in a LiveView process in steady state. The "fresh process" scenario shows the cold case, and "process spawn only" is what to subtract from it.

  Run: `just test extensions/bonfire_common/test/modularity/apply_modules_cached_benchmark_test.exs --only benchmark`
  """
  use ExUnit.Case, async: false

  @moduletag :backend
  @moduletag :benchmark
  @moduletag timeout: :infinity

  alias Bonfire.Common.ContextModule
  alias Bonfire.Common.Extend
  alias Bonfire.Common.SettingsHookModule

  # a module that is enabled in any test run
  @enabled_module Bonfire.Posts
  # a schema declared by a context module, so its lookup goes through the cached maps
  @schema Bonfire.Data.Social.Post

  @tag :benchmark
  test "registry lookups: cost per call" do
    user = %{id: "bench_user", settings: %Bonfire.Data.Identity.Settings{json: %{}}}
    settings = %{bonfire_social: %{some_key: 1}}

    # correctness first, so the numbers are for lookups that resolve
    assert is_map(ContextModule.linked_schema_modules())
    assert {:ok, _context} = ContextModule.context_module(@schema)
    assert Extend.module_enabled?(@enabled_module)
    assert Extend.module_enabled?(@enabled_module, current_user: user)
    assert SettingsHookModule.apply_hooks(settings, :bonfire_social) == settings

    IO.puts("\n=== registry lookups (p50/p99) ===")

    Benchee.run(
      %{
        "apply_modules_cached (ContextModule.linked_schema_modules)" => fn ->
          ContextModule.linked_schema_modules()
        end,
        "ContextModule.context_module(schema)" => fn -> ContextModule.context_module(@schema) end,
        "module_enabled?(module), warm process cache" => fn ->
          Extend.module_enabled?(@enabled_module)
        end,
        "module_enabled?(module, current_user: user), warm process cache" => fn ->
          Extend.module_enabled?(@enabled_module, current_user: user)
        end,
        "module_enabled?(module) in a fresh process" => fn ->
          Task.async(fn -> Extend.module_enabled?(@enabled_module) end) |> Task.await()
        end,
        "process spawn only (subtract from the fresh process row)" => fn ->
          Task.async(fn -> :ok end) |> Task.await()
        end,
        "SettingsHookModule.apply_hooks(settings, :unrelated_app)" => fn ->
          SettingsHookModule.apply_hooks(settings, :bonfire_social)
        end
      },
      warmup: 2,
      time: 4,
      percentiles: [50, 99],
      print: [fast_warning: false]
    )
  end
end
