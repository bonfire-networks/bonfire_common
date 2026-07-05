defmodule Bonfire.Common.Settings.Calm.InstanceTuningTest do
  @moduledoc """
  Instance performance tuning as a Calm consumer: a knob REGISTRY with per-knob type/bounds/tiers, transforms incl. `{:step, n}` over tiers, values validated (typed, clamped, whitelisted, but never interpolated), and a swappable APPLIER that receives only the DIFF of changed knobs.
  """
  use ExUnit.Case, async: false

  alias Bonfire.Common.Settings.Calm.InstanceTuning
  alias Bonfire.Common.Config

  defmodule TestApplier do
    def apply_changes(changes) do
      send(:instance_tuning_test_proc, {:applied, changes})
      :ok
    end

    def read_baseline(_registry), do: %{}
    def pending_restart, do: []
  end

  # a small hermetic registry (the real one lives in runtime config)
  @registry [
    work_mem: [
      layer: :postgres,
      context: :user,
      type: :int,
      unit: "kB",
      bounds: {4_096, 524_288},
      tiers: [16_384, 32_768, 65_536, 131_072, 262_144]
    ],
    jit: [layer: :postgres, context: :user, type: :bool],
    autovacuum_vacuum_cost_limit: [
      layer: :postgres,
      context: :sighup,
      type: :int,
      bounds: {100, 10_000}
    ]
  ]

  @config_keys [
    :knob_registry,
    :preset_names,
    :presets,
    :cards,
    :groups,
    :preset,
    :knobs,
    :overrides,
    :applier
  ]

  setup do
    Process.register(self(), :instance_tuning_test_proc)

    Config.put([InstanceTuning, :applier], TestApplier)
    Config.put([InstanceTuning, :knob_registry], @registry)
    Config.put([InstanceTuning, :preset_names], [:eco, :default, :turbo, :custom])

    Config.put([InstanceTuning, :presets],
      eco: [work_mem: {:scale, 0.5}],
      turbo: [work_mem: {:scale, 2.0}, autovacuum_vacuum_cost_limit: {:set, 2000}]
    )

    Config.put([InstanceTuning, :groups],
      faster_feeds: [name: "Faster feeds", knobs: [work_mem: {:step, 1}]],
      quiet: [name: "Quiet", knobs: [jit: {:set, "off"}]]
    )

    Config.put([InstanceTuning, :preset], :default)
    Config.put([InstanceTuning, :knobs], %{})
    Config.put([InstanceTuning, :overrides], %{})

    InstanceTuning.put_baseline(%{work_mem: 65_536, jit: "on", autovacuum_vacuum_cost_limit: 200})

    on_exit(fn ->
      Enum.each(@config_keys, &Config.delete([InstanceTuning, &1]))
      InstanceTuning.reset_baseline()
      # unregister happens automatically when the test process dies
    end)

    :ok
  end

  describe "transforms over the registry" do
    test "{:scale, f} clamps into the knob's bounds" do
      # 65_536 * 2.0 = 131_072 (within bounds)
      assert InstanceTuning.effective_for_preset(:turbo)[:work_mem] == 131_072

      # scale far past the max clamps to the bound
      Config.put([InstanceTuning, :presets], turbo: [work_mem: {:scale, 100.0}])
      assert InstanceTuning.effective_for_preset(:turbo)[:work_mem] == 524_288
    end

    test "{:step, n} moves along the knob's tiers; edges clamp" do
      Config.put([InstanceTuning, :overrides], %{faster_feeds: true})
      # baseline 65_536 is tier 3 of 5 → +1 = 131_072
      assert InstanceTuning.effective()[:work_mem] == 131_072

      # from the top tier, +1 stays at the top
      InstanceTuning.put_baseline(%{
        work_mem: 262_144,
        jit: "on",
        autovacuum_vacuum_cost_limit: 200
      })

      assert InstanceTuning.effective()[:work_mem] == 262_144
    end

    test "{:step, n} from a baseline between tiers snaps to the nearest then steps" do
      InstanceTuning.put_baseline(%{
        work_mem: 50_000,
        jit: "on",
        autovacuum_vacuum_cost_limit: 200
      })

      Config.put([InstanceTuning, :overrides], %{faster_feeds: true})

      # nearest tier to 50_000 is 65_536? (|50000-32768|=17232 < |65536-50000|=15536 → 65_536) → +1 = 131_072
      assert InstanceTuning.effective()[:work_mem] == 131_072
    end

    test "{:set, v} applies literally; toggles compose on the preset" do
      Config.put([InstanceTuning, :preset], :turbo)
      Config.put([InstanceTuning, :overrides], %{quiet: true})

      effective = InstanceTuning.effective()
      assert effective[:jit] == "off"
      assert effective[:autovacuum_vacuum_cost_limit] == 2000
    end
  end

  describe "normalize_value/2 (typed, clamped, never raw)" do
    test "int knobs accept integers and numeric strings, clamped into bounds" do
      assert InstanceTuning.normalize_value(:work_mem, 65_536) == 65_536
      assert InstanceTuning.normalize_value(:work_mem, "65536") == 65_536
      assert InstanceTuning.normalize_value(:work_mem, 1) == 4_096
      assert InstanceTuning.normalize_value(:work_mem, 9_999_999) == 524_288
      assert InstanceTuning.normalize_value(:work_mem, "not a number") == nil
    end

    test "bool knobs accept on/off/true/false, reject junk" do
      assert InstanceTuning.normalize_value(:jit, "on") == "on"
      assert InstanceTuning.normalize_value(:jit, "off") == "off"
      assert InstanceTuning.normalize_value(:jit, true) == "on"
      assert InstanceTuning.normalize_value(:jit, false) == "off"
      assert InstanceTuning.normalize_value(:jit, "DROP TABLE") == nil
    end

    test "unknown knobs are dropped from stored values (whitelist)" do
      Config.put([InstanceTuning, :preset], :custom)

      Config.put([InstanceTuning, :knobs], %{
        "shared_preload_libraries" => "evil",
        work_mem: 32_768
      })

      assert InstanceTuning.effective() == %{work_mem: 32_768}
    end
  end

  describe "apply_current/0 (diffs to the applier)" do
    test "first apply sends the diff vs baseline; unchanged re-apply sends nothing" do
      Config.put([InstanceTuning, :preset], :turbo)

      assert {:ok, changes} = InstanceTuning.apply_current()
      assert_receive {:applied, ^changes}
      assert changes[:work_mem] == 131_072
      assert changes[:autovacuum_vacuum_cost_limit] == 2000
      # jit unchanged from baseline → not in the diff
      refute Map.has_key?(changes, :jit)

      # nothing changed → applier not called again
      assert {:ok, %{} = empty} = InstanceTuning.apply_current()
      assert empty == %{}
      refute_receive {:applied, _}, 100
    end

    test "a later change diffs only the newly-changed knobs" do
      Config.put([InstanceTuning, :preset], :turbo)
      {:ok, _} = InstanceTuning.apply_current()
      assert_receive {:applied, _}

      Config.put([InstanceTuning, :knobs], %{work_mem: 65_536})
      assert {:ok, changes} = InstanceTuning.apply_current()
      assert_receive {:applied, ^changes}

      # only work_mem moved (back to baseline value); cost_limit already applied
      assert changes == %{work_mem: 65_536}
    end
  end

  describe "PostgresApplier statement building (pure, whitelisted)" do
    alias Bonfire.Common.Settings.Calm.InstanceTuning.PostgresApplier

    test "builds typed literals, never interpolating raw strings" do
      registry = @registry

      assert PostgresApplier.build_statement(:work_mem, 65_536, registry) ==
               {:ok, "ALTER SYSTEM SET work_mem = 65536"}

      assert PostgresApplier.build_statement(:jit, "off", registry) ==
               {:ok, "ALTER SYSTEM SET jit = off"}
    end

    test "rejects knobs not in the registry and mistyped values" do
      assert {:error, _} =
               PostgresApplier.build_statement(:shared_preload_libraries, "x", @registry)

      assert {:error, _} =
               PostgresApplier.build_statement(:work_mem, "65536; DROP TABLE", @registry)

      assert {:error, _} = PostgresApplier.build_statement(:jit, "maybe", @registry)
    end
  end
end
