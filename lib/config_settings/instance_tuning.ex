defmodule Bonfire.Common.Settings.Calm.InstanceTuning do
  @moduledoc """
  Admin-tunable instance performance settings, as a `Bonfire.Common.Settings.Calm` consumer (plan: postgres-ops-tuning.md › C2) — currently the **Postgres layer**: reload-safe server settings applied live via a whitelisted `ALTER SYSTEM SET` + `pg_reload_conf()` applier.

  The tunables live in a config **knob registry** (`:knob_registry`) with per-knob metadata: `layer:`, `context:` (`:user`/`:sighup` apply on reload; `:postmaster` persists but needs a DB restart — surfaced, never auto-restarted), `type:` (`:int` | `:bool` | `:real`), `bounds:` (ints clamp into them), `tiers:` (an ordered ladder powering the `{:step, n}` transform — how "work_mem one tier up" works). Presets and Level-2 override toggles are transforms over the BOOT BASELINE (a `pg_settings` snapshot taken on first use — boot config stays the single source of truth; presets only express intent on top).

  `apply_current/0` computes the effective values and hands the applier only the DIFF vs what was last applied (initially the baseline), so unchanged knobs are never re-set. The applier is swappable via config `:applier` (tests use a mock; the default is `#{inspect(__MODULE__)}.PostgresApplier`).

  Values are typed, clamped and whitelisted — raw admin input is NEVER interpolated into SQL.
  """
  use Bonfire.Common.Config
  alias Bonfire.Common.Settings.Calm
  alias Bonfire.Common.Types
  require Logger

  @behaviour Calm

  @keys [preset: :preset, values: :knobs, toggles: :overrides]
  @baseline_key {__MODULE__, :baseline}
  @last_applied_key {__MODULE__, :last_applied}

  # ── registry ────────────────────────────────────────────────────────────────

  @doc "The knob registry: `knob => [layer:, context:, type:, bounds:, tiers:, ...]` (config `:knob_registry`)."
  def registry, do: Config.get([__MODULE__, :knob_registry], [])

  @doc "A single knob's registry entry."
  def knob_spec(knob), do: Keyword.get(registry(), knob, [])

  # ── Calm callbacks ──────────────────────────────────────────────────────────

  @impl Calm
  def knobs, do: Keyword.keys(registry())

  @impl Calm
  def baseline do
    case :persistent_term.get(@baseline_key, nil) do
      %{} = baseline ->
        baseline

      _ ->
        baseline = applier().read_baseline(registry())
        if baseline != %{}, do: put_baseline(baseline)
        baseline
    end
  end

  @doc "Set the boot baseline (called at boot with the pg_settings snapshot; also the test seam)."
  def put_baseline(%{} = baseline) do
    :persistent_term.put(@baseline_key, baseline)
    :ok
  end

  @doc "Forget the baseline and last-applied snapshots (tests)."
  def reset_baseline do
    :persistent_term.erase(@baseline_key)
    :persistent_term.erase(@last_applied_key)
    :ok
  end

  @impl Calm
  def normalize_value(knob, value), do: normalize_typed(knob_spec(knob), value)

  defp normalize_typed(spec, value) do
    case Keyword.get(spec, :type, :int) do
      :int -> Types.maybe_to_integer(value, nil) |> clamp_to(Keyword.get(spec, :bounds))
      :bool -> guc_bool(value)
      :real -> Types.maybe_to_float(value, nil)
    end
  end

  defp clamp_to(val, {lo, hi}), do: Types.maybe_clamp(val, lo, hi)
  defp clamp_to(val, _), do: val

  # pg boolean GUCs use on/off literals (not true/false)
  defp guc_bool(value) do
    case Types.maybe_to_boolean(value) do
      true -> "on"
      false -> "off"
      nil -> nil
    end
  end

  @impl Calm
  def transform(knob, base, tf), do: do_transform(knob_spec(knob), base, tf)

  defp do_transform(_spec, base, :baseline), do: base
  defp do_transform(spec, _base, {:set, value}), do: normalize_typed(spec, value)

  defp do_transform(spec, base, {:scale, factor}) when is_number(base),
    do: clamp_to(trunc(base * factor), Keyword.get(spec, :bounds))

  defp do_transform(spec, base, {:step, n}) when is_number(base) do
    case Keyword.get(spec, :tiers) do
      tiers when is_list(tiers) and tiers != [] ->
        # snap the baseline to its nearest tier, then move n positions (edges clamp)
        nearest = Enum.min_by(0..(length(tiers) - 1), fn i -> abs(Enum.at(tiers, i) - base) end)
        Enum.at(tiers, (nearest + n) |> max(0) |> min(length(tiers) - 1))

      _ ->
        base
    end
  end

  defp do_transform(_spec, base, _), do: base

  # Level-2 toggles: each group's config lists its knob transforms directly
  @impl Calm
  def toggle_transforms(group_opts) do
    group_opts
    |> Keyword.get(:knobs, [])
    |> Map.new(fn {knob, tf} -> {knob, tf} end)
  end

  # ── current state / effective values ────────────────────────────────────────

  @doc "The available preset names, in UI order."
  def preset_names, do: Calm.preset_names(__MODULE__)

  @doc "Per-preset UI metadata."
  def cards, do: Calm.cards(__MODULE__)

  @doc "The currently-selected preset."
  def current_preset, do: Calm.current_preset(__MODULE__, @keys[:preset])

  @doc "Level-2 override toggle definitions."
  def toggle_groups, do: Calm.toggle_groups(__MODULE__)

  @doc "Which Level-2 toggles are on."
  def current_overrides, do: Calm.current_toggles(__MODULE__, @keys[:toggles])

  @doc "Sparse Level-3 knob values."
  def current_knobs, do: Calm.current_values(__MODULE__, @keys[:values])

  @doc """
  Effective knob values: preset transforms over the baseline → toggled override bundles → sparse
  knob values (most specific wins).
  """
  def effective, do: Calm.effective(__MODULE__, @keys)

  # presets here are per-knob transform lists (config `:presets`), not uniform multipliers
  @impl Calm
  def preset_transforms(preset), do: Config.get([__MODULE__, :presets], []) |> Keyword.get(preset)

  @doc "A preset's values over the current baseline (preview / delta display)."
  def effective_for_preset(preset), do: Calm.values_for_preset(__MODULE__, preset) || %{}

  # ── apply ────────────────────────────────────────────────────────────────────

  @doc "The live applier module (config `:applier`; swappable for tests)."
  def applier, do: Config.get([__MODULE__, :applier], __MODULE__.PostgresApplier)

  @doc """
  Apply the current effective values: compute the diff vs what was last applied (initially the
  baseline) and hand ONLY the changed knobs to the applier. Returns `{:ok, changes}`.
  Called from the `Bonfire.Common.Settings` save hook after any preset/override/knob change.
  """
  def apply_current do
    last = :persistent_term.get(@last_applied_key, nil) || baseline()
    target = Map.merge(baseline(), effective())

    changes =
      for {knob, value} <- target, Map.get(last, knob) != value, into: %{} do
        {knob, value}
      end

    with :ok <- apply_changes(changes) do
      :persistent_term.put(@last_applied_key, target)
      {:ok, changes}
    end
  end

  defp apply_changes(changes) when changes == %{}, do: :ok

  defp apply_changes(changes) do
    case applier().apply_changes(changes) do
      :ok ->
        :ok

      e ->
        Logger.warning("InstanceTuning: applier failed: #{inspect(e)}")
        e
    end
  end

  @doc "Knobs persisted but awaiting a DB restart (surfaced as a badge in the UI, never auto-restarted)."
  def pending_restart, do: applier().pending_restart()

  defmodule DisabledApplier do
    @moduledoc "No-op applier: for managed DBs without ALTER SYSTEM rights, and the safe test-env default (a real applier would persist ALTER SYSTEMs into the test DB)."
    def apply_changes(_changes), do: :ok
    def read_baseline(_registry), do: %{}
    def pending_restart, do: []
  end

  defmodule PostgresApplier do
    @moduledoc """
    The Postgres side of `Bonfire.Common.Settings.Calm.InstanceTuning`: applies knob changes via `ALTER SYSTEM SET` + `pg_reload_conf()` (reload-safe for `user`/`sighup`-context params; `postmaster` ones persist and show up in `pending_restart/0`).

    Statements are built ONLY from registry-whitelisted knob names and typed, validated values — raw input never reaches SQL. Feature-detected: requires the DB user to be able to `ALTER SYSTEM` (true on the recipe's bundled Postgres; managed DBs get a read-only UI).
    """
    alias Bonfire.Common.Repo
    alias Bonfire.Common.Settings.Calm.InstanceTuning
    require Logger

    @doc "Whether this DB connection can ALTER SYSTEM (superuser)."
    def available? do
      case Repo.query("SELECT current_setting('is_superuser') = 'on'", [], timeout: 5_000) do
        {:ok, %{rows: [[true]]}} -> true
        _ -> false
      end
    rescue
      _ -> false
    end

    @doc "Read the current pg_settings values for the registry's postgres-layer knobs (the boot baseline)."
    def read_baseline(registry) do
      names = for {knob, spec} <- registry, spec[:layer] == :postgres, do: to_string(knob)

      case Repo.query(
             "SELECT name, setting FROM pg_settings WHERE name = ANY($1)",
             [names],
             timeout: 5_000
           ) do
        {:ok, %{rows: rows}} ->
          for [name, setting] <- rows,
              knob = String.to_existing_atom(name),
              value = parse_setting(Keyword.get(registry, knob, []), setting),
              not is_nil(value),
              into: %{} do
            {knob, value}
          end

        _ ->
          %{}
      end
    rescue
      _ -> %{}
    catch
      _, _ -> %{}
    end

    defp parse_setting(spec, setting) do
      case Keyword.get(spec, :type, :int) do
        :int ->
          case Integer.parse(setting) do
            {i, _} -> i
            _ -> nil
          end

        :bool ->
          if setting in ["on", "off"], do: setting

        :real ->
          case Float.parse(setting) do
            {f, _} -> f
            _ -> nil
          end
      end
    end

    @doc "Apply the changed knobs: one whitelisted ALTER SYSTEM per knob, then a single reload."
    def apply_changes(changes) do
      registry = InstanceTuning.registry()

      results =
        for {knob, value} <- changes do
          with {:ok, sql} <- build_statement(knob, value, registry),
               {:ok, _} <- Repo.query(sql, [], timeout: 10_000) do
            :ok
          else
            e ->
              Logger.warning("InstanceTuning: could not apply #{knob}: #{inspect(e)}")
              {:error, knob}
          end
        end

      Repo.query("SELECT pg_reload_conf()", [], timeout: 5_000)

      if Enum.all?(results, &(&1 == :ok)), do: :ok, else: {:error, :partial_apply}
    rescue
      e -> {:error, e}
    end

    @doc """
    Build the ALTER SYSTEM statement for one knob — pure and safe by construction: the knob must
    be in the registry (whitelist) and the value must round-trip the knob's type (typed literal,
    no string interpolation of raw input).
    """
    def build_statement(knob, value, registry) do
      with spec when spec != [] <- Keyword.get(registry, knob, []),
           {:ok, literal} <- typed_literal(Keyword.get(spec, :type, :int), value) do
        {:ok, "ALTER SYSTEM SET #{knob} = #{literal}"}
      else
        [] -> {:error, {:unknown_knob, knob}}
        e -> e
      end
    end

    defp typed_literal(:int, value) when is_integer(value), do: {:ok, Integer.to_string(value)}
    defp typed_literal(:bool, value) when value in ["on", "off"], do: {:ok, value}
    defp typed_literal(:real, value) when is_number(value), do: {:ok, to_string(value * 1.0)}
    defp typed_literal(type, value), do: {:error, {:invalid_value, type, value}}

    @doc "Params persisted via ALTER SYSTEM that need a DB restart to take effect."
    def pending_restart do
      case Repo.query("SELECT name FROM pg_settings WHERE pending_restart", [], timeout: 5_000) do
        {:ok, %{rows: rows}} -> List.flatten(rows)
        _ -> []
      end
    rescue
      _ -> []
    end
  end
end
