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

  # read-only registry rows (boot-time env knobs, displayed with env-var hints) are never settable
  @impl Calm
  def knobs, do: for({knob, spec} <- registry(), !spec[:read_only], do: knob)

  @impl Calm
  def baseline do
    case :persistent_term.get(@baseline_key, nil) do
      %{} = baseline ->
        baseline

      _ ->
        # each layer's applier reads its own knobs' boot values
        baseline =
          Enum.reduce(appliers(), %{}, fn {layer, applier}, acc ->
            Map.merge(acc, applier.read_baseline(layer_registry(layer)))
          end)

        if baseline != %{}, do: put_baseline(baseline)
        baseline
    end
  end

  defp layer_registry(layer),
    do:
      for(
        {knob, spec} <- registry(),
        spec[:layer] == layer && !spec[:read_only],
        do: {knob, spec}
      )

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

  # stored percents may range from a tenth to 4x of the baseline
  @percent_bounds {10, 400}

  @impl Calm
  def normalize_value(knob, value) do
    spec = knob_spec(knob)

    if spec[:relative],
      # relative knobs STORE a percent-of-baseline (resolved at effective-time), so admin
      # intent survives resource changes, the deploy tuner and admin tuning never fight
      do: Types.maybe_to_integer(value, nil) |> clamp_to(@percent_bounds),
      else: normalize_typed(spec, value)
  end

  @doc """
  Resolve a stored Level-3 value into the applied value: relative knobs store a percent of the
  CURRENT baseline (recomputable after resizes); everything else is stored absolute.
  """
  @impl Calm
  def resolve_value(knob, stored) do
    spec = knob_spec(knob)

    if spec[:relative] && is_number(stored),
      do: clamp_to(trunc((Map.get(baseline(), knob) || 0) * stored / 100), spec[:bounds]),
      else: stored
  end

  defp normalize_typed(spec, value) do
    case Keyword.get(spec, :type, :int) do
      :int -> Types.maybe_to_integer(value, nil) |> clamp_to(Keyword.get(spec, :bounds))
      :bool -> guc_bool(value)
      :real -> Types.maybe_to_float(value, nil)
      :enum -> to_enum(value, Keyword.get(spec, :values, []))
    end
  end

  # enum values are whitelisted atoms; accepts the string form, or an INDEX into the ordered
  # values list (enums render as discrete sliders — range inputs submit numbers)
  defp to_enum(value, values) when is_atom(value) and not is_nil(value),
    do: if(value in values, do: value)

  defp to_enum(index, values) when is_integer(index),
    do: Enum.at(values, Types.maybe_clamp(index, 0, length(values) - 1))

  defp to_enum(value, values) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> to_enum(index, values)
      _ -> to_enum(Types.maybe_to_atom!(value), values)
    end
  end

  defp to_enum(_, _), do: nil

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

  @doc "The live applier module per layer (config `:appliers`; swappable for tests/managed DBs)."
  def appliers do
    Config.get([__MODULE__, :appliers],
      postgres: __MODULE__.PostgresApplier,
      elixir: __MODULE__.ElixirApplier
    )
  end

  @doc """
  Apply the current effective values: compute the diff vs what was last applied (initially the
  baseline) and hand ONLY the changed knobs to each LAYER's applier. Returns `{:ok, changes}`.
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
    results =
      for {layer, applier} <- appliers(),
          slice = Map.filter(changes, fn {knob, _} -> knob_spec(knob)[:layer] == layer end),
          slice != %{} do
        case applier.apply_changes(slice) do
          :ok ->
            :ok

          e ->
            Logger.warning("InstanceTuning: #{layer} applier failed: #{inspect(e)}")
            e
        end
      end

    if Enum.all?(results, &(&1 == :ok)), do: :ok, else: {:error, :partial_apply}
  end

  @doc "Knobs persisted but awaiting a DB restart (surfaced as a badge in the UI, never auto-restarted)."
  def pending_restart do
    Enum.flat_map(appliers(), fn {_layer, applier} -> applier.pending_restart() end)
  end

  defmodule ElixirApplier do
    @moduledoc """
    The Elixir/app side of `Bonfire.Common.Settings.Calm.InstanceTuning`: applies runtime-mutable app knobs (log levels via `Logger.configure/1`, EctoSparkles query-logging settings via app env — both read at call time, so changes are live).

    Each knob has an explicit clause (whitelist by construction); anything else is ignored with a warning.
    """
    require Logger

    def apply_changes(changes) do
      Enum.each(changes, &apply_one/1)
      :ok
    end

    defp apply_one({:app_log_level, level}) when is_atom(level),
      do: Logger.configure(level: level)

    # NOTE these project the EFFECTIVE value into the app env the reading code consumes at call
    # time (EctoSparkles does Application.get_env) — the durable copy is the admin's intent in
    # Settings, re-projected on boot/apply. Config.put is the canonical wrapper (test-scoped too).
    defp apply_one({:ecto_slow_query_ms, ms}) when is_integer(ms),
      do: Bonfire.Common.Config.put(:slow_query_ms, ms, :ecto_sparkles)

    defp apply_one({:ecto_queries_log_level, level}) when is_atom(level),
      do: Bonfire.Common.Config.put(:queries_log_level, level, :ecto_sparkles)

    # NPlus1Reporter.setup/0 attaches or detaches the span-end handlers based on the flag we
    # just projected — N+1 detection has ZERO attached telemetry handlers while off (same
    # attach-on-enable principle as the page profiler)
    defp apply_one({:n_plus_1_detect, value}) do
      Bonfire.Common.Config.put(:n_plus_1_detect, value in [true, "on"], :ecto_sparkles)
      EctoSparkles.NPlus1Reporter.setup()
    end

    # LIVE: LV reads endpoint.config(:live_view)[:hibernate_after] from the endpoint's mutable
    # ETS config per mount — config_change updates it, new mounts pick it up, no restart
    defp apply_one({:lv_hibernate_after, ms}) when is_integer(ms) do
      endpoint = Bonfire.Common.Config.endpoint_module()

      if function_exported?(endpoint, :config_change, 2) do
        live_view = Keyword.put(endpoint.config(:live_view) || [], :hibernate_after, ms)
        endpoint.config_change([{endpoint, [live_view: live_view]}], [])
      else
        Logger.warning("InstanceTuning: no endpoint to apply lv_hibernate_after to")
      end
    end

    defp apply_one({knob, value}),
      do:
        Logger.warning("InstanceTuning: no elixir applier clause for #{knob} = #{inspect(value)}")

    def read_baseline(registry) do
      for {knob, _spec} <- registry, value = current_value(knob), not is_nil(value), into: %{} do
        {knob, value}
      end
    end

    defp current_value(:app_log_level), do: Logger.level()

    defp current_value(:ecto_slow_query_ms),
      do: Application.get_env(:ecto_sparkles, :slow_query_ms, 100)

    defp current_value(:ecto_queries_log_level),
      do: Application.get_env(:ecto_sparkles, :queries_log_level, :debug)

    defp current_value(:n_plus_1_detect),
      do: if(EctoSparkles.NPlus1Detector.enabled?(), do: "on", else: "off")

    defp current_value(:lv_hibernate_after) do
      endpoint = Bonfire.Common.Config.endpoint_module()

      if function_exported?(endpoint, :config, 2),
        do: Keyword.get(endpoint.config(:live_view) || [], :hibernate_after)
    rescue
      # endpoint config ETS may not exist yet (boot order) — baseline retries on next read
      _ -> nil
    end

    defp current_value(_), do: nil

    def pending_restart, do: []
  end

  defmodule DisabledApplier do
    @moduledoc "No-op applier: for managed DBs without ALTER SYSTEM rights, and the safe test-env default (a real applier would persist ALTER SYSTEMs into the test DB)."
    def apply_changes(_changes), do: :ok
    def read_baseline(_registry), do: %{}
    def pending_restart, do: []
  end

  defmodule PostgresApplier do
    @moduledoc """
    The Postgres side of `Bonfire.Common.Settings.Calm.InstanceTuning`: applies knob changes via `ALTER SYSTEM SET` + `pg_reload_conf()` (reload-safe for `user`/`sighup`-context params; `postmaster` ones persist and show up in `pending_restart/0`).

    Statements are built ONLY from registry-whitelisted knob names and typed, validated values. Raw input never reaches SQL. Feature-detected: requires the DB user to be able to `ALTER SYSTEM` (true on the recipe's bundled Postgres; managed DBs get a read-only UI).
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

    @doc """
    Read the current pg_settings values for the registry's postgres-layer knobs (the boot baseline),
    converted from each GUC's native unit (pg_settings.unit — kB, 8kB, ms, s, min, B...) into the
    registry's HUMAN unit (e.g. work_mem in MB), so every number the admin sees is sensible.
    """
    def read_baseline(registry) do
      names = for {knob, spec} <- registry, spec[:layer] == :postgres, do: to_string(knob)

      case Repo.query(
             "SELECT name, setting, unit FROM pg_settings WHERE name = ANY($1)",
             [names],
             timeout: 5_000
           ) do
        {:ok, %{rows: rows}} ->
          for [name, setting, pg_unit] <- rows,
              knob = String.to_existing_atom(name),
              value = parse_setting(Keyword.get(registry, knob, []), setting, pg_unit),
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

    defp parse_setting(spec, setting, pg_unit) do
      case Keyword.get(spec, :type, :int) do
        :int ->
          case Integer.parse(setting) do
            {i, _} -> convert_unit(i, pg_unit, Keyword.get(spec, :unit))
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

    # bytes per pg memory unit / ms per pg time unit
    @unit_bytes %{
      "B" => 1,
      "kB" => 1_024,
      "8kB" => 8_192,
      "MB" => 1_048_576,
      "GB" => 1_073_741_824
    }
    @unit_ms %{"ms" => 1, "s" => 1_000, "min" => 60_000, "h" => 3_600_000}

    # sentinels (-1 = disabled, 0 = special) are never unit-scaled
    defp convert_unit(value, _from, _to) when value <= 0, do: value
    defp convert_unit(value, same, same), do: value
    defp convert_unit(value, nil, _to), do: value
    defp convert_unit(value, _from, nil), do: value

    defp convert_unit(value, from, to) do
      cond do
        @unit_bytes[from] && @unit_bytes[to] ->
          max(1, round(value * @unit_bytes[from] / @unit_bytes[to]))

        @unit_ms[from] && @unit_ms[to] ->
          max(1, round(value * @unit_ms[from] / @unit_ms[to]))

        true ->
          value
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
    no string interpolation of raw input). Registry units become pg unit-suffixed literals
    (`work_mem = '64MB'`); sentinel values (<= 0) are emitted bare (`'-1MB'` would be invalid).
    """
    def build_statement(knob, value, registry) do
      with spec when spec != [] <- Keyword.get(registry, knob, []),
           {:ok, literal} <-
             typed_literal(Keyword.get(spec, :type, :int), value, Keyword.get(spec, :unit)) do
        {:ok, "ALTER SYSTEM SET #{knob} = #{literal}"}
      else
        [] -> {:error, {:unknown_knob, knob}}
        e -> e
      end
    end

    defp typed_literal(:int, value, unit) when is_integer(value) do
      if is_binary(unit) and value > 0,
        do: {:ok, "'#{value}#{unit}'"},
        else: {:ok, Integer.to_string(value)}
    end

    defp typed_literal(:bool, value, _unit) when value in ["on", "off"], do: {:ok, value}

    defp typed_literal(:real, value, _unit) when is_number(value),
      do: {:ok, to_string(value * 1.0)}

    defp typed_literal(type, value, _unit), do: {:error, {:invalid_value, type, value}}

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
