defmodule Bonfire.Common.ObanPresets do
  @moduledoc """
  Runtime, admin-switchable throughput presets for the Oban background queues (#1638).

  Federation/import/etc. run as Oban background jobs; on small/shared servers a burst can saturate the Ecto pool. An instance admin picks a preset and the effective limits are applied **live** via `Oban.scale_queue/2` (no restart) and are how Oban **boots** (see `start_oban/1`, wired from `Bonfire.Application.maybe_oban/1`).

  Effective limits = preset base → prioritised groups → per-queue overrides:
  - **Preset** (`[ObanPresets, :preset]`): `:default` = the env-configured baseline; `:custom` = overrides-only; every other preset (e.g. `:eco`, `:turbo`) scales the baseline by its config `:multipliers` factor, applied to **all** managed queues.
  - **Prioritised groups** (`:prioritised_groups`): toggling a config-defined `:groups` group runs its queues at the `:turbo` (2×) level on top of the preset.
  - **Per-queue overrides** (`:queues`): a sparse `%{queue => limit}` map (the "Custom" / advanced layer).
  """
  use Bonfire.Common.Config
  alias Bonfire.Common.Config
  alias Bonfire.Common.Types
  require Logger

  @preset_key :preset
  @overrides_key :queues

  # Preset names + multipliers live in config (`config :bonfire_common, Bonfire.Common.ObanPresets, ...`);
  # `:default` (env baseline) and `:custom` (overrides-only) are the only built-ins.

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

  @doc "The available preset names, in UI order (config `:preset_names`)."
  def preset_names, do: Config.get([__MODULE__, :preset_names], [:default, :custom])

  @doc "Preset name => env multiplier, as a keyword list (config `:multipliers`)."
  def multipliers, do: Config.get([__MODULE__, :multipliers], [])

  @doc "Per-preset UI metadata (`name`, `icon`, `description`) as a keyword list (config `:cards`)."
  def cards, do: Config.get([__MODULE__, :cards], [])

  @doc """
  Base per-queue limits for a named preset, before per-queue overrides. `:default` = the env-configured
  baseline (`env_limits/0`), `:custom` = nil (overrides-only); every other preset scales the baseline by
  its `multipliers/0` factor (min 1), e.g. `:eco` = half, `:turbo` = double.
  """
  def limits_for(preset)

  def limits_for(:default), do: env_limits()
  def limits_for(:custom), do: nil
  def limits_for(preset) when is_binary(preset), do: limits_for(normalize_preset(preset))

  def limits_for(preset) when is_atom(preset) do
    case Keyword.get(multipliers(), preset) do
      nil -> env_limits()
      factor -> scale_env(fn n -> max(1, trunc(n * factor)) end)
    end
  end

  def limits_for(_), do: limits_for(:default)

  defp scale_env(fun), do: Map.new(env_limits(), fn {queue, limit} -> {queue, fun.(limit)} end)

  @doc "The currently-configured preset (from the instance setting / Config), default `:default`."
  def current_preset do
    Config.get([__MODULE__, @preset_key], :default)
    |> normalize_preset()
  end

  @doc "Sparse per-queue overrides currently configured (from the instance setting / Config)."
  def current_overrides do
    Config.get([__MODULE__, @overrides_key], %{})
    |> normalize_overrides()
  end

  @doc """
  Named federation queue groups for the Layer-2 "prioritise" toggles (config `:groups`),
  as `group => [name:, description:, queues:]`.
  """
  def queue_groups, do: Config.get([__MODULE__, :groups], [])

  @doc "The queues belonging to a group."
  def group_queues(group) do
    queue_groups()
    |> Keyword.get(group, [])
    |> Keyword.get(:queues, [])
    |> List.wrap()
  end

  @doc "Which groups are currently prioritised, as `group => boolean` (from the instance setting)."
  def current_priorities do
    Config.get([__MODULE__, :prioritised_groups], [])
    |> normalize_priorities()
  end

  @doc "All queues in the currently-prioritised groups."
  def prioritised_queues do
    current_priorities()
    |> Enum.flat_map(fn {group, on} -> if(on, do: group_queues(group), else: []) end)
  end

  @doc """
  Effective per-queue limits: the preset base, then any **prioritised groups** bumped to the `turbo`
  (2×) level, then the sparse per-queue overrides (most specific wins).
  """
  def effective_limits do
    base = limits_for(current_preset()) || %{}

    base
    |> Map.merge(Map.take(limits_for(:turbo), prioritised_queues()))
    |> Map.merge(current_overrides())
  end

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
    case limits_for(normalize_preset(preset)) do
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

  defp normalize_preset(preset) when is_atom(preset) and not is_nil(preset),
    do: if(preset in preset_names(), do: preset, else: :default)

  # `maybe_to_atom!` returns nil (not the string) for an unknown name, so this can't recurse forever
  defp normalize_preset(preset) when is_binary(preset),
    do: normalize_preset(Types.maybe_to_atom!(preset))

  defp normalize_preset(_), do: :default

  defp normalize_overrides(overrides) when is_map(overrides) or is_list(overrides) do
    for {queue, limit} <- overrides,
        queue_atom = to_known_queue(queue),
        not is_nil(queue_atom),
        limit_int = Types.maybe_to_pos_integer(limit),
        not is_nil(limit_int),
        into: %{} do
      {queue_atom, limit_int}
    end
  end

  defp normalize_overrides(_), do: %{}

  defp to_known_queue(queue) when is_atom(queue),
    do: if(queue in managed_queues(), do: queue)

  defp to_known_queue(queue) when is_binary(queue),
    do: to_known_queue(Types.maybe_to_atom!(queue))

  defp to_known_queue(_), do: nil

  defp normalize_priorities(priorities) when is_map(priorities) or is_list(priorities) do
    for {group, on} <- priorities, g = to_known_group(group), not is_nil(g), into: %{} do
      {g, truthy?(on)}
    end
  end

  defp normalize_priorities(_), do: %{}

  defp to_known_group(group) when is_atom(group),
    do: if(Keyword.has_key?(queue_groups(), group), do: group)

  defp to_known_group(group) when is_binary(group),
    do: to_known_group(Types.maybe_to_atom!(group))

  defp to_known_group(_), do: nil

  defp truthy?(v), do: v in [true, "true", "on", "1", 1]
end
