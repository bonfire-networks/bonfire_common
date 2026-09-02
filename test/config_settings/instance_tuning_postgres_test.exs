defmodule Bonfire.Common.Settings.Calm.InstanceTuningPostgresTest do
  @moduledoc """
  `Bonfire.Common.Settings.Calm.InstanceTuning` against a real Postgres, via the real `PostgresApplier` (the rest of the suite uses mock appliers, so this is the only cover for the round trip from `apply_changes/1` back through `read_baseline/1`).

  A preset is a transform over the DEPLOY's configuration. The baseline it transforms is therefore the value Postgres would report if the tuning feature had never run, whatever the admin has saved and however many times the app has booted. Turbo means "twice what this deploy configured", so applying it on ten successive boots lands on the same value every time.

  `ALTER SYSTEM` cannot run inside a transaction block, so this module opts out of the SQL sandbox (`db_sandbox: false`) and resets what it touched instead of relying on a rollback. Bear in mind `ALTER SYSTEM` is cluster-wide, not per-database.
  """
  use Bonfire.Common.DataCase, async: false

  @moduletag db_sandbox: false

  alias Bonfire.Common.Config
  alias Bonfire.Common.Repo
  alias Bonfire.Common.Settings.Calm.InstanceTuning

  # `work_mem` rather than an inert logging GUC: the baseline has to come from a source the tuning
  # feature does not itself write, which leaves the compiled-in default as the only option a test
  # can rely on. The log_* knobs default to -1 (disabled), so scaling them proves nothing, and
  # seeding them via ALTER SYSTEM would be seeding the very file under test. `work_mem` defaults to
  # a usable positive number, and the values here stay in single-digit MB.
  @knob :work_mem

  @registry [
    work_mem: [
      layer: :postgres,
      context: :user,
      type: :int,
      unit: "MB",
      bounds: {4, 2_048}
    ]
  ]

  @config_keys [:knob_registry, :preset_names, :presets, :preset, :knobs, :overrides, :appliers]

  setup do
    # the baseline and last-applied snapshots live in `:persistent_term`, i.e. global to the node:
    # start from a known state rather than trusting whatever ran before to have tidied up
    reset_knob!()
    InstanceTuning.reset_baseline()

    Config.put([InstanceTuning, :appliers], postgres: InstanceTuning.PostgresApplier)
    Config.put([InstanceTuning, :knob_registry], @registry)
    Config.put([InstanceTuning, :preset_names], [:default, :turbo, :custom])
    Config.put([InstanceTuning, :presets], turbo: [work_mem: {:scale, 2.0}])
    Config.put([InstanceTuning, :preset], :default)
    Config.put([InstanceTuning, :knobs], %{})
    Config.put([InstanceTuning, :overrides], %{})

    on_exit(fn ->
      reset_knob!()
      InstanceTuning.reset_baseline()
      Enum.each(@config_keys, &Config.delete([InstanceTuning, &1]))
    end)

    # every assertion below is meaningless without ALTER SYSTEM rights, so say so plainly rather
    # than failing somewhere further in
    assert InstanceTuning.PostgresApplier.available?(),
           "this test needs a superuser connection to run ALTER SYSTEM"

    {:ok, deploy_default: read_knob_mb!()}
  end

  describe "the baseline is the deploy's configuration" do
    test "an applied knob is written to postgresql.auto.conf", %{deploy_default: base} do
      Config.put([InstanceTuning, :preset], :turbo)

      assert {:ok, changes} = InstanceTuning.apply_current()
      assert changes[@knob] == base * 2

      # durable config rather than a session setting — which is exactly what makes it a candidate
      # baseline on the next boot, since Postgres loads this file at startup
      assert written_to_auto_conf_mb!() == base * 2
    end

    test "a second boot applies the preset over the deploy default, not over its own last output",
         %{deploy_default: base} do
      Config.put([InstanceTuning, :preset], :turbo)

      assert {:ok, first} = InstanceTuning.apply_current()
      assert first[@knob] == base * 2

      # Establish the precondition a restart always has, rather than racing it. `pg_settings`
      # serves a value per backend, updated only once that backend handles the `pg_reload_conf/0`
      # SIGHUP, so reading it straight after a write is a coin toss. A booting app never sees that
      # ambiguity: it connects to a Postgres that already loaded postgresql.auto.conf at startup.
      await_visible!(base * 2)

      # a restart, as far as this module is concerned: `:persistent_term` does not survive one, so
      # the next boot re-derives the baseline and re-asserts the admin's saved intent on top
      # (see `LoadInstanceConfig.reassert_instance_tuning/0`)
      InstanceTuning.reset_baseline()

      rederived_baseline = InstanceTuning.baseline()[@knob]
      assert {:ok, second} = InstanceTuning.apply_current()

      # One assertion over the whole chain, so a failure names WHICH link broke rather than only
      # the outcome. `baseline_on_second_boot` is the positive control: if it reads the deploy
      # default rather than the previous run's write, then the premise never held and a passing
      # outcome would prove nothing.
      assert %{
               baseline_on_second_boot: base,
               applied_on_second_boot: base * 2,
               in_auto_conf: base * 2
             } ==
               %{
                 baseline_on_second_boot: rederived_baseline,
                 applied_on_second_boot: Map.get(second, @knob, base * 2),
                 in_auto_conf: written_to_auto_conf_mb!()
               }
    end
  end

  describe "reset_to_defaults/0" do
    test "puts an applied knob back to what the deploy configures", %{deploy_default: base} do
      Config.put([InstanceTuning, :preset], :turbo)
      assert {:ok, %{@knob => applied}} = InstanceTuning.apply_current()
      assert applied == base * 2
      await_visible!(base * 2)

      assert {:ok, _} = InstanceTuning.reset_to_defaults()

      # the write is gone from postgresql.auto.conf, so nothing carries into the next boot
      assert written_to_auto_conf_mb!() == nil
      await_visible!(base)
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  # block until a reloaded value is actually being served, so the assertions after it are testing
  # behaviour rather than timing
  defp await_visible!(expected_mb, tries \\ 100) do
    cond do
      read_knob_mb!() == expected_mb ->
        :ok

      tries > 0 ->
        Process.sleep(20)
        await_visible!(expected_mb, tries - 1)

      true ->
        flunk("pg_settings never reported #{@knob} = #{expected_mb} MB after pg_reload_conf/0")
    end
  end

  # what ALTER SYSTEM actually persisted, read back from the file rather than from `pg_settings`
  # (which is per-session and lags a reload). `nil` when the knob is absent from the file.
  defp written_to_auto_conf_mb! do
    %{rows: rows} =
      Repo.query!(
        "SELECT setting FROM pg_file_settings WHERE name = $1 AND sourcefile LIKE '%auto.conf'",
        [to_string(@knob)]
      )

    case rows do
      [[setting] | _] -> setting |> String.trim_trailing("MB") |> String.to_integer()
      [] -> nil
    end
  end

  # `work_mem`'s native unit is kB; the registry (and so every number above) is in MB
  defp read_knob_mb! do
    %{rows: [[setting]]} =
      Repo.query!("SELECT setting FROM pg_settings WHERE name = $1", [to_string(@knob)])

    String.to_integer(setting) |> div(1024)
  end

  defp reset_knob! do
    Repo.query!("ALTER SYSTEM RESET #{@knob}")
    Repo.query!("SELECT pg_reload_conf()")
  end
end
