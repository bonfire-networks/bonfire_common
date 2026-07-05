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

  defmodule ElixirTestApplier do
    def apply_changes(changes) do
      send(:instance_tuning_test_proc, {:applied_elixir, changes})
      :ok
    end

    def read_baseline(_registry), do: %{}
    def pending_restart, do: []
  end

  # a small hermetic registry (the real one lives in runtime config); units are HUMAN units
  @registry [
    work_mem: [
      layer: :postgres,
      context: :user,
      type: :int,
      unit: "MB",
      bounds: {4, 512},
      tiers: [16, 32, 64, 128, 256]
    ],
    jit: [layer: :postgres, context: :user, type: :bool],
    autovacuum_vacuum_cost_limit: [
      layer: :postgres,
      context: :sighup,
      type: :int,
      bounds: {100, 10_000}
    ],
    log_temp_files: [
      layer: :postgres,
      context: :user,
      type: :int,
      unit: "MB",
      bounds: {-1, 1_024}
    ],
    app_log_level: [
      layer: :elixir,
      type: :enum,
      values: [:debug, :info, :warning, :error]
    ],
    maintenance_mem: [
      layer: :postgres,
      context: :user,
      type: :int,
      unit: "MB",
      bounds: {16, 4_096},
      relative: true
    ],
    pool_size: [layer: :elixir, read_only: true, env: "POOL_SIZE"]
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
    :appliers
  ]

  setup do
    Process.register(self(), :instance_tuning_test_proc)

    Config.put([InstanceTuning, :appliers], postgres: TestApplier, elixir: ElixirTestApplier)
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

    InstanceTuning.put_baseline(%{
      work_mem: 64,
      jit: "on",
      autovacuum_vacuum_cost_limit: 200,
      app_log_level: :info,
      maintenance_mem: 128
    })

    on_exit(fn ->
      Enum.each(@config_keys, &Config.delete([InstanceTuning, &1]))
      InstanceTuning.reset_baseline()
      # unregister happens automatically when the test process dies
    end)

    :ok
  end

  describe "transforms over the registry" do
    test "{:scale, f} clamps into the knob's bounds" do
      # 64 * 2.0 = 128 (within bounds)
      assert InstanceTuning.effective_for_preset(:turbo)[:work_mem] == 128

      # scale far past the max clamps to the bound
      Config.put([InstanceTuning, :presets], turbo: [work_mem: {:scale, 100.0}])
      assert InstanceTuning.effective_for_preset(:turbo)[:work_mem] == 512
    end

    test "{:step, n} moves along the knob's tiers; edges clamp" do
      Config.put([InstanceTuning, :overrides], %{faster_feeds: true})
      # baseline 64 is tier 3 of 5 → +1 = 128
      assert InstanceTuning.effective()[:work_mem] == 128

      # from the top tier, +1 stays at the top
      InstanceTuning.put_baseline(%{
        work_mem: 256,
        jit: "on",
        autovacuum_vacuum_cost_limit: 200
      })

      assert InstanceTuning.effective()[:work_mem] == 256
    end

    test "{:step, n} from a baseline between tiers snaps to the nearest then steps" do
      InstanceTuning.put_baseline(%{
        work_mem: 50,
        jit: "on",
        autovacuum_vacuum_cost_limit: 200
      })

      Config.put([InstanceTuning, :overrides], %{faster_feeds: true})

      # nearest tier to 50 is 64 (|50-32|=18 > |64-50|=14) → +1 = 128
      assert InstanceTuning.effective()[:work_mem] == 128
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
      assert InstanceTuning.normalize_value(:work_mem, 64) == 64
      assert InstanceTuning.normalize_value(:work_mem, "64") == 64
      assert InstanceTuning.normalize_value(:work_mem, 1) == 4
      assert InstanceTuning.normalize_value(:work_mem, 9_999_999) == 512
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
        work_mem: 32
      })

      assert InstanceTuning.effective() == %{work_mem: 32}
    end
  end

  describe "apply_current/0 (diffs to the applier)" do
    test "first apply sends the diff vs baseline; unchanged re-apply sends nothing" do
      Config.put([InstanceTuning, :preset], :turbo)

      assert {:ok, changes} = InstanceTuning.apply_current()
      assert_receive {:applied, ^changes}
      assert changes[:work_mem] == 128
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

      Config.put([InstanceTuning, :knobs], %{work_mem: 64})
      assert {:ok, changes} = InstanceTuning.apply_current()
      assert_receive {:applied, ^changes}

      # only work_mem moved (back to baseline value); cost_limit already applied
      assert changes == %{work_mem: 64}
    end
  end

  describe "enum + read-only knobs" do
    test "enum knobs whitelist their values (string form accepted)" do
      assert InstanceTuning.normalize_value(:app_log_level, :warning) == :warning
      assert InstanceTuning.normalize_value(:app_log_level, "warning") == :warning
      assert InstanceTuning.normalize_value(:app_log_level, "sudo") == nil
    end

    test "enum knobs accept a slider index into the ordered values (clamped)" do
      assert InstanceTuning.normalize_value(:app_log_level, 2) == :warning
      assert InstanceTuning.normalize_value(:app_log_level, "2") == :warning
      assert InstanceTuning.normalize_value(:app_log_level, 99) == :error
    end

    test "read-only knobs are not settable (excluded from the whitelist)" do
      Config.put([InstanceTuning, :preset], :custom)
      Config.put([InstanceTuning, :knobs], %{pool_size: 99, app_log_level: :error})

      assert InstanceTuning.effective() == %{app_log_level: :error}
      refute :pool_size in InstanceTuning.knobs()
    end
  end

  describe "relative knobs (stored as % of baseline — survives resizes)" do
    test "stored values are percents, clamped to sane bounds" do
      assert InstanceTuning.normalize_value(:maintenance_mem, 150) == 150
      assert InstanceTuning.normalize_value(:maintenance_mem, "150") == 150
      assert InstanceTuning.normalize_value(:maintenance_mem, 9_999) == 400
      assert InstanceTuning.normalize_value(:maintenance_mem, 1) == 10
    end

    test "effective resolves the percent over the CURRENT baseline — the resize property" do
      Config.put([InstanceTuning, :preset], :custom)
      Config.put([InstanceTuning, :knobs], %{maintenance_mem: 200})

      # 200% of the 128 MB baseline
      assert InstanceTuning.effective()[:maintenance_mem] == 256

      # the "VPS resize": tuner recomputes the baseline; the SAME stored intent re-resolves
      InstanceTuning.put_baseline(%{
        work_mem: 64,
        jit: "on",
        autovacuum_vacuum_cost_limit: 200,
        app_log_level: :info,
        maintenance_mem: 512
      })

      assert InstanceTuning.effective()[:maintenance_mem] == 1_024
    end

    test "resolution clamps into the knob's absolute bounds" do
      Config.put([InstanceTuning, :preset], :custom)
      Config.put([InstanceTuning, :knobs], %{maintenance_mem: 400})

      InstanceTuning.put_baseline(%{maintenance_mem: 2_048})
      assert InstanceTuning.effective()[:maintenance_mem] == 4_096
    end
  end

  describe "per-layer applier routing" do
    test "each layer's applier receives only its own knobs" do
      Config.put([InstanceTuning, :preset], :turbo)
      Config.put([InstanceTuning, :knobs], %{app_log_level: :error})

      assert {:ok, _} = InstanceTuning.apply_current()

      assert_receive {:applied, pg_changes}
      assert Map.keys(pg_changes) |> Enum.sort() == [:autovacuum_vacuum_cost_limit, :work_mem]

      assert_receive {:applied_elixir, elixir_changes}
      assert elixir_changes == %{app_log_level: :error}
    end
  end

  describe "PostgresApplier statement building (pure, whitelisted)" do
    alias Bonfire.Common.Settings.Calm.InstanceTuning.PostgresApplier

    test "builds typed literals, never interpolating raw strings" do
      registry = @registry

      assert PostgresApplier.build_statement(:work_mem, 64, registry) ==
               {:ok, "ALTER SYSTEM SET work_mem = '64MB'"}

      # unit-less int knobs emit bare integers
      assert PostgresApplier.build_statement(:autovacuum_vacuum_cost_limit, 2000, registry) ==
               {:ok, "ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 2000"}

      # sentinels are never unit-suffixed ('-1MB' would be invalid)
      assert PostgresApplier.build_statement(:log_temp_files, -1, registry) ==
               {:ok, "ALTER SYSTEM SET log_temp_files = -1"}

      assert PostgresApplier.build_statement(:jit, "off", registry) ==
               {:ok, "ALTER SYSTEM SET jit = off"}
    end

    test "rejects knobs not in the registry and mistyped values" do
      assert {:error, _} =
               PostgresApplier.build_statement(:shared_preload_libraries, "x", @registry)

      assert {:error, _} =
               PostgresApplier.build_statement(:work_mem, "64; DROP TABLE", @registry)

      assert {:error, _} = PostgresApplier.build_statement(:jit, "maybe", @registry)
    end
  end
end
