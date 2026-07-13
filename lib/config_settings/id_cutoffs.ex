defmodule Bonfire.Common.Settings.IdCutoffs do
  @moduledoc """
  Records and reads per-instance chronological ID cutoffs.

  A cutoff pins a representation or behaviour change to "objects created after this instance upgraded": since UIDs sort chronologically, comparing an object's ID to a cutoff recorded once, at the first boot where the feature is present, deterministically partitions pre-existing objects from new ones, without any data migration, and correctly for every instance regardless of when it upgrades (a date shipped in code could not do this: instances upgrading late would have pre-upgrade objects created after it).

  Keys to record are declared in config as a keyword list — keyword lists deep-merge across `config` declarations, so any extension can register its own keys without clobbering others' (set a key to `false` to unregister):

      config :bonfire_common, Bonfire.Common.Settings.IdCutoffs, record: [ulid_actor_ids_since: true]

  At boot (as a transient GenServer placed after `Bonfire.Common.Settings.LoadInstanceConfig`, so already-recorded cutoffs have been loaded from DB into Config) each declared key with no recorded value gets the current UID stored in instance settings under `[__MODULE__, :recorded, key]`: durable in the DB, mirrored into OTP config immediately, and reloaded into Config on subsequent boots:

      config :bonfire_common, Bonfire.Common.Settings.IdCutoffs, recorded: [ulid_actor_ids_since: "01J..."]

  Read a cutoff back with `cutoff/1` (or compare directly with `after?/2`). Since the recorded value lives in instance settings, admins can inspect/adjust it in the settings. Recording is usually skipped in the test env: `config/test.exs` records epoch-zero cutoffs instead so the suite runs new-format behaviour by default (like a fresh instance); a test covering legacy behaviour sets a far-future cutoff via `Application.put_env(:bonfire_common, __MODULE__, recorded: [the_key: "7ZZZ..."])` (or `Process.put([:bonfire_common, __MODULE__, :recorded, :the_key], ...)` for in-process reads only).

  First used for `:ulid_actor_ids_since` (see `Bonfire.Common.URIs` docs on the actor URL scheme); intended to be reused for the ULID → prefixed UUIDv7 migration (per-schema `prefixed_ids_since`).
  """
  use GenServer, restart: :transient
  require Logger
  use Bonfire.Common.Config
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Settings

  @spec start_link(ignored :: term) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  @doc false
  def init(_) do
    record_declared()
    :ignore
  end

  @doc "Records any declared-but-unrecorded cutoffs (see `keys_to_record/0`). Skipped in the test env."
  def record_declared do
    if Config.env() != :test do
      Enum.each(keys_to_record(), &ensure_recorded/1)
    end
  end

  @doc "The cutoff keys declared for recording at boot (keys of the `:record` keyword list whose value is truthy)."
  def keys_to_record,
    do: for({key, truthy} <- Config.get([__MODULE__, :record], []), truthy, do: key)

  @doc """
  Records a current UID as this instance's cutoff for `key`, unless one is already recorded. Returns `{:ok, cutoff}` with the (existing or newly recorded) cutoff, or `:error` (logged, never raises — must not break boot).
  """
  def ensure_recorded(key) do
    case cutoff(key) do
      nil -> record(key, Needle.UID.generate())
      existing -> {:ok, existing}
    end
  end

  defp record(key, value) do
    # persists to instance settings in DB + mirrors into OTP config right away
    with {:ok, _} <-
           Settings.put([__MODULE__, :recorded, key], value,
             skip_boundary_check: true,
             scope: :instance
           ) do
      Logger.info("Recorded instance ID cutoff #{inspect(key)} = #{value}")
      {:ok, value}
    end
  rescue
    e ->
      Logger.warning("Could not record instance ID cutoff #{inspect(key)}: #{inspect(e)}")
      :error
  end

  @doc "The recorded cutoff UID for `key` (from `[#{inspect(__MODULE__)}, :recorded, key]`), or nil when unset/blank."
  def cutoff(key) do
    Enums.filter_empty(Config.get([__MODULE__, :recorded, key], nil), nil)
  end

  @doc "True if `id` sorts after the recorded cutoff for `key` (i.e. was created after this instance recorded it). False when no cutoff is recorded."
  def after?(key, id) when is_binary(id) do
    case cutoff(key) do
      nil -> false
      cutoff -> id > cutoff
    end
  end

  def after?(_key, _id), do: false
end
