defmodule Bonfire.Common.Settings.Calm do
  @moduledoc """
  The engine behind Bonfire's *calm empowerment* settings pattern: admin-facing tuning surfaces built as three layers of progressive disclosure, all reducing onto the same set of knobs —

  1. **Preset cards** (Level 1): one choice among a few outcome-named presets. `:default` is always the boot/env-configured baseline and `:custom` means "overrides only"; every other preset is a *transform over the baseline*, never a frozen value set — so correctly-sized boot config stays the single source of truth and presets only express intent on top.
  2. **Curated override toggles** (Level 2): outcome-named toggles that each bump a small bundle of knobs, composing ON TOP of the preset without changing it.
  3. **Advanced knob values** (Level 3): a sparse `%{knob => value}` map, most specific wins. Editing any knob flips the preset to `:custom` (declaratively, via the UI's hidden inputs — see `Bonfire.UI.Common` settings components).

  Effective values = preset base → toggled bundles → sparse knob values.

  Consumers (e.g. `Bonfire.Common.ObanPresets`) implement the small behaviour below and keep their own config namespace (`config :bonfire_common, MyConsumer, preset_names: ..., multipliers: ..., cards: ..., groups: ...`) and Settings keys, so existing stored settings keep working. All state is read through `Bonfire.Common.Config` (i.e. instance Settings once loaded), and every read normalizes: unknown presets fall back to `:default`, unknown knobs/toggles are dropped, values go through the consumer's `normalize_value/2`.

  ## Transforms

  Preset and toggle values are expressed as transforms over the baseline value of each knob:

  - `:baseline` — the boot/env value, unchanged
  - `{:scale, factor}` — numeric scaling (default impl clamps to min 1 via `max(1, trunc(value * factor))`; override `transform/3` for knobs with other units/bounds)
  - `{:set, value}` — a literal value
  - `{:preset_level, preset}` — this knob at another preset's level (how "prioritise this group = run it at turbo" works)
  """

  use Bonfire.Common.Config
  alias Bonfire.Common.Types

  @typedoc "A tunable's name (for Oban: a queue name)"
  @type knob :: atom
  @type transform ::
          :baseline | {:scale, number} | {:set, term} | {:preset_level, atom}

  @doc "The Level-3 knob names this consumer manages."
  @callback knobs() :: [knob]

  @doc "The boot/env-configured value per knob — the `:default` preset IS this."
  @callback baseline() :: %{knob => term}

  @doc "Validate/coerce a stored or form-submitted value for a knob; nil drops it."
  @callback normalize_value(knob, term) :: term | nil

  @doc "Apply a transform to a knob's baseline value (optional — see default impl in `transform/4`)."
  @callback transform(knob, base :: term, transform) :: term

  @doc "The knob transforms a Level-2 toggle applies, from its config entry (optional)."
  @callback toggle_transforms(group_opts :: Keyword.t()) :: %{knob => transform}

  @doc "Per-knob transforms for a preset (optional — for consumers whose presets aren't uniform multipliers); nil = baseline."
  @callback preset_transforms(preset :: atom) :: [{knob, transform}] | nil

  @optional_callbacks transform: 3, toggle_transforms: 1, preset_transforms: 1

  # ── config readers (namespaced under the consumer module) ─────────────────

  @doc "The available preset names, in UI order (consumer config `:preset_names`)."
  def preset_names(mod), do: Config.get([mod, :preset_names], [:default, :custom])

  @doc "Preset name => baseline multiplier, as a keyword list (consumer config `:multipliers`)."
  def multipliers(mod), do: Config.get([mod, :multipliers], [])

  @doc "Per-preset UI metadata (`name`, `icon`, `description`) (consumer config `:cards`)."
  def cards(mod), do: Config.get([mod, :cards], [])

  @doc "Level-2 toggle definitions, as `group => [name:, description:, ...]` (consumer config `:groups`)."
  def toggle_groups(mod), do: Config.get([mod, :groups], [])

  # ── current state (instance Settings, read via Config) ────────────────────

  @doc "The currently-configured preset under the given settings key, normalized (unknown → `:default`)."
  def current_preset(mod, key) do
    Config.get([mod, key], :default)
    |> normalize_preset(mod)
  end

  @doc "The sparse Level-3 values under the given settings key, normalized (unknown knobs/invalid values dropped)."
  def current_values(mod, key) do
    Config.get([mod, key], %{})
    |> normalize_values(mod)
  end

  @doc "Which Level-2 toggles are on, as `group => boolean`, normalized (unknown groups dropped)."
  def current_toggles(mod, key) do
    Config.get([mod, key], [])
    |> normalize_toggles(mod)
  end

  # ── preset resolution ──────────────────────────────────────────────────────

  @doc """
  Base per-knob values for a named preset, before toggles/overrides. `:default` = the consumer's
  `baseline/0`, `:custom` = nil (overrides-only); other presets scale the baseline by their
  `multipliers/1` factor (via `transform/4`), unknown presets fall back to the baseline.
  """
  def values_for_preset(mod, preset)

  def values_for_preset(mod, :default), do: mod.baseline()
  def values_for_preset(_mod, :custom), do: nil

  def values_for_preset(mod, preset) when is_binary(preset),
    do: values_for_preset(mod, normalize_preset(preset, mod))

  def values_for_preset(mod, preset) when is_atom(preset) and not is_nil(preset) do
    # consumers with heterogeneous knobs define per-knob transforms per preset;
    # simpler consumers (e.g. ObanPresets) use one multiplier across all knobs
    cond do
      function_exported?(mod, :preset_transforms, 1) ->
        case mod.preset_transforms(preset) do
          transforms when is_list(transforms) ->
            Enum.reduce(transforms, mod.baseline(), fn {knob, tf}, acc ->
              Map.put(acc, knob, transform(mod, knob, Map.get(mod.baseline(), knob), tf))
            end)

          _ ->
            mod.baseline()
        end

      factor = Keyword.get(multipliers(mod), preset) ->
        Map.new(mod.baseline(), fn {k, v} -> {k, transform(mod, k, v, {:scale, factor})} end)

      true ->
        mod.baseline()
    end
  end

  def values_for_preset(mod, _), do: values_for_preset(mod, :default)

  # ── the reducer ────────────────────────────────────────────────────────────

  @doc """
  Effective per-knob values: the preset base, then any toggled Level-2 bundles, then the sparse
  Level-3 values (most specific wins). `keys` names the consumer's settings keys, e.g.
  `[preset: :preset, values: :queues, toggles: :prioritised_groups]`.
  """
  def effective(mod, keys) do
    base = values_for_preset(mod, current_preset(mod, keys[:preset])) || %{}

    base
    |> Map.merge(toggled_values(mod, keys[:toggles]))
    |> Map.merge(current_values(mod, keys[:values]))
  end

  @doc "The knob values contributed by the currently-ON Level-2 toggles."
  def toggled_values(mod, key) do
    for {group, true} <- current_toggles(mod, key),
        {knob, tf} <- toggle_transforms(mod, group),
        into: %{} do
      {knob, resolve_transform(mod, knob, tf)}
    end
  end

  defp toggle_transforms(mod, group) do
    group_opts = Keyword.get(toggle_groups(mod), group, [])

    if function_exported?(mod, :toggle_transforms, 1),
      do: mod.toggle_transforms(group_opts),
      else: %{}
  end

  defp resolve_transform(mod, knob, {:preset_level, preset}),
    do: Map.get(values_for_preset(mod, preset) || %{}, knob)

  defp resolve_transform(mod, knob, tf),
    do: transform(mod, knob, Map.get(mod.baseline(), knob), tf)

  @doc "Apply a transform to a knob's baseline value, using the consumer's `transform/3` when defined."
  def transform(mod, knob, base, tf) do
    if function_exported?(mod, :transform, 3),
      do: mod.transform(knob, base, tf),
      else: default_transform(base, tf)
  end

  defp default_transform(base, :baseline), do: base
  defp default_transform(_base, {:set, value}), do: value

  defp default_transform(base, {:scale, factor}) when is_number(base),
    do: max(1, trunc(base * factor))

  defp default_transform(base, _), do: base

  # ── normalization ──────────────────────────────────────────────────────────

  @doc "Normalize a preset name: whitelisted atom, or string→known atom; anything else → `:default`."
  def normalize_preset(preset, mod) when is_atom(preset) and not is_nil(preset),
    do: if(preset in preset_names(mod), do: preset, else: :default)

  # `maybe_to_atom!` returns nil (not the string) for an unknown name, so this can't recurse forever
  def normalize_preset(preset, mod) when is_binary(preset),
    do: normalize_preset(Types.maybe_to_atom!(preset), mod)

  def normalize_preset(_, _mod), do: :default

  @doc "Normalize sparse knob values: unknown knobs and values rejected by `normalize_value/2` are dropped."
  def normalize_values(values, mod) when is_map(values) or is_list(values) do
    for {knob, value} <- values,
        knob_atom = to_known(knob, mod.knobs()),
        not is_nil(knob_atom),
        normalized = mod.normalize_value(knob_atom, value),
        not is_nil(normalized),
        into: %{} do
      {knob_atom, normalized}
    end
  end

  def normalize_values(_, _mod), do: %{}

  @doc "Normalize the toggles map: unknown groups dropped, values coerced to booleans."
  def normalize_toggles(toggles, mod) when is_map(toggles) or is_list(toggles) do
    known = Keyword.keys(toggle_groups(mod))

    for {group, on} <- toggles, g = to_known(group, known), not is_nil(g), into: %{} do
      {g, truthy?(on)}
    end
  end

  def normalize_toggles(_, _mod), do: %{}

  @doc "Resolve an atom-or-string name against a whitelist (nil when unknown)."
  def to_known(name, known) when is_atom(name) and not is_nil(name),
    do: if(name in known, do: name)

  def to_known(name, known) when is_binary(name),
    do: to_known(Types.maybe_to_atom!(name), known)

  def to_known(_, _), do: nil

  @doc "Form-input-tolerant boolean check."
  def truthy?(v), do: v in [true, "true", "on", "1", 1]
end
