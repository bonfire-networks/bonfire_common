defmodule Bonfire.Common.ObanPresets do
  @moduledoc """
  Runtime, admin-switchable throughput presets for the Oban background queues (#1638).

  Federation/import/etc. run as Oban background jobs; on small/shared servers a burst can saturate the Ecto pool. An instance admin picks a preset and the effective limits are applied **live** via `Oban.scale_queue/2` (no restart) and are how Oban **boots** (see `start_oban/1`, wired from `Bonfire.Application.maybe_oban/1`).

  Built on `Bonfire.Common.Settings.Calm` (the shared calm-empowerment engine, this module was its first consumer and keeps its original config namespace + settings keys). Effective limits = preset base → prioritised groups → per-queue overrides:
  - **Preset** (`[ObanPresets, :preset]`): `:default` = the env-configured baseline; `:custom` = overrides-only; every other preset (e.g. `:eco`, `:turbo`) scales the baseline by its config `:multipliers` factor, applied to **all** managed queues.
  - **Prioritised groups** (`:prioritised_groups`): toggling a config-defined `:groups` group runs its queues at the `:turbo` (2×) level on top of the preset.
  - **Per-queue overrides** (`:queues`): a sparse `%{queue => limit}` map (the "Custom" / advanced layer).
  """
  use Bonfire.Common.Config
  alias Bonfire.Common.Config
  alias Bonfire.Common.Settings.Calm
  alias Bonfire.Common.Types
  require Logger

  @behaviour Calm

  # the settings keys, kept verbatim from before the Calm extraction (stored instance settings)
  @keys [preset: :preset, values: :queues, toggles: :prioritised_groups]

  # ── Calm callbacks: knobs are the managed queues, values are positive ints ──

  @impl Calm
  def knobs, do: managed_queues()

  @impl Calm
  def baseline, do: env_limits()

  @impl Calm
  def normalize_value(_queue, limit), do: Types.maybe_to_pos_integer(limit)

  # a prioritised group = its queues at the turbo level, on top of the preset
  @impl Calm
  def toggle_transforms(group_opts) do
    group_opts
    |> Keyword.get(:queues, [])
    |> List.wrap()
    |> Map.new(&{&1, {:preset_level, :turbo}})
  end

  # ── queues ──────────────────────────────────────────────────────────────────

  @doc """
  All Oban queues the presets manage. Defaults to **every** queue in the Oban config (so it stays
  in sync), overridable via config `:managed_queues`.
  """
  def managed_queues, do: Config.get([__MODULE__, :managed_queues], oban_queue_names())

  @doc """
  The federation subset of the managed queues — used only to group the quick overrides in the UI.
  Overridable via config `:federation_queues`, else derived from queue names (`federator_*` + `remote_fetcher`).
  """
  def federation_queues do
    Config.get([__MODULE__, :federation_queues]) ||
      Enum.filter(managed_queues(), &federation_queue?/1)
  end

  defp federation_queue?(queue) do
    name = to_string(queue)
    String.starts_with?(name, "federator") or name == "remote_fetcher"
  end

  # ── presets/cards/groups (delegated to the Calm engine, same config shape) ──

  @doc "The available preset names, in UI order (config `:preset_names`)."
  def preset_names, do: Calm.preset_names(__MODULE__)

  @doc "Preset name => env multiplier, as a keyword list (config `:multipliers`)."
  def multipliers, do: Calm.multipliers(__MODULE__)

  @doc "Per-preset UI metadata (`name`, `icon`, `description`) as a keyword list (config `:cards`)."
  def cards, do: Calm.cards(__MODULE__)

  @doc """
  Base per-queue limits for a named preset, before per-queue overrides. `:default` = the env-configured
  baseline (`baseline/0`), `:custom` = nil (overrides-only); every other preset scales the baseline by
  its `multipliers/0` factor (min 1), e.g. `:eco` = half, `:turbo` = double.
  """
  def limits_for(preset), do: Calm.values_for_preset(__MODULE__, preset)

  @doc "The currently-configured preset (from the instance setting / Config), default `:default`."
  def current_preset, do: Calm.current_preset(__MODULE__, @keys[:preset])

  @doc "Sparse per-queue overrides currently configured (from the instance setting / Config)."
  def current_overrides, do: Calm.current_values(__MODULE__, @keys[:values])

  @doc """
  Named federation queue groups for the Layer-2 "prioritise" toggles (config `:groups`),
  as `group => [name:, description:, queues:]`.
  """
  def queue_groups, do: Calm.toggle_groups(__MODULE__)

  @doc "The queues belonging to a group."
  def group_queues(group) do
    queue_groups()
    |> Keyword.get(group, [])
    |> Keyword.get(:queues, [])
    |> List.wrap()
  end

  @doc "Which groups are currently prioritised, as `group => boolean` (from the instance setting)."
  def current_priorities, do: Calm.current_toggles(__MODULE__, @keys[:toggles])

  @doc "All queues in the currently-prioritised groups."
  def prioritised_queues do
    current_priorities()
    |> Enum.flat_map(fn {group, on} -> if(on, do: group_queues(group), else: []) end)
  end

  @doc """
  Effective per-queue limits: the preset base, then any **prioritised groups** bumped to the `turbo`
  (2×) level, then the sparse per-queue overrides (most specific wins).
  """
  def effective_limits, do: Calm.effective(__MODULE__, @keys)

  # ── Oban-specific: boot + live apply ────────────────────────────────────────

  @doc """
  Lazy boot entrypoint for the Oban child (called by the supervisor when starting Oban, *after*
  instance settings are loaded into Config) — merges the effective preset limits into the queue
  config and starts Oban.
  """
  def start_oban(base_config) do
    base_config
    |> merge_into_config()
    |> Oban.start_link()
  end

  @doc "Merge the effective federation limits into an Oban config's `:queues` (pure; used by `start_oban/1`)."
  def merge_into_config(base_config) do
    Keyword.update(base_config, :queues, [], fn
      queues when is_list(queues) ->
        Enum.reduce(effective_limits(), queues, fn {queue, limit}, acc ->
          Keyword.put(acc, queue, limit)
        end)

      other ->
        other
    end)
  end

  @doc "Apply the given preset (live) to all running Oban instances."
  def apply_preset(preset) do
    case limits_for(preset) do
      nil -> :ok
      limits -> apply_limits(limits)
    end
  end

  @doc """
  Apply the current effective limits (preset + overrides) live to all running Oban instances.
  Called from the `Bonfire.Common.Settings` save hook after the preset/overrides change.
  """
  def apply_current, do: apply_limits(effective_limits())

  def apply_limits(limits \\ effective_limits())

  def apply_limits(limits) when is_map(limits) and map_size(limits) > 0 do
    for name <- running_instances(), {queue, limit} <- limits do
      case Oban.scale_queue(name, queue: queue, limit: limit) do
        :ok ->
          :ok

        {:error, e} ->
          Logger.warning(
            "ObanPresets: could not scale #{queue} on #{inspect(name)}: #{inspect(e)}"
          )
      end
    end

    :ok
  end

  def apply_limits(_), do: :ok

  # all Oban instances that are actually running (main + test-instance), so it's a safe no-op
  # when Oban isn't started (e.g. test env with queues disabled)
  defp running_instances do
    [Oban, Oban.TestInstance]
    |> Enum.filter(fn name -> Oban.whereis(name) != nil end)
  end

  # the env/boot-configured limits for the managed queues
  defp env_limits do
    queues = oban_queues_config()

    for queue <- managed_queues(), into: %{} do
      {queue, Keyword.get(queues, queue, 1)}
    end
  end

  defp oban_queues_config do
    case Keyword.get(Application.get_env(:bonfire, Oban, []), :queues, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # all queue names known to the Oban config (so `managed_queues` stays in sync by default)
  defp oban_queue_names, do: Keyword.keys(oban_queues_config())
end
