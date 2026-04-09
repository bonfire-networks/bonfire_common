defmodule Bonfire.Common.Cache.BenchmarkHelpers do
  @moduledoc """
  Shared helpers for cache benchmarks (`CacheBackendBenchmark`, `StaticServingBenchmark`, etc.).

  Provides:
  - Cache flushing + GC between scenarios
  - ETS + Nebulex memory measurement
  - Byte formatting
  - Benchee formatter for ETS size delta reporting
  """

  alias Bonfire.Common.Cache.NebulexLocalCache
  alias Bonfire.Common.Cache.NebulexCoherentCache

  @behaviour Benchee.Formatter

  # ---------------------------------------------------------------------------
  # Cache flushing
  # ---------------------------------------------------------------------------

  @doc "Flush all known cache backends and run a full GC on all processes."
  def flush_all do
    Cachex.clear(:bonfire_cache)
    NebulexLocalCache.delete_all()
    NebulexCoherentCache.delete_all()
    if Code.loaded?(Bonfire.Common.Cache.DiskLFUCache), do: Bonfire.Common.Cache.DiskLFUCache.delete_all()
    :erlang.garbage_collect()
    for pid <- Process.list(), do: :erlang.garbage_collect(pid)
    :ok
  end

  # ---------------------------------------------------------------------------
  # ETS + Nebulex memory measurement
  # ---------------------------------------------------------------------------

  @doc """
  Total bytes used by all tracked cache ETS tables plus Nebulex Local/Coherent.

  ETS tables are tracked via `:persistent_term` key `:cache_tables` — call
  `init_cache_tables/0` once after starting your cache processes to register them.
  """
  def cache_mem do
    wordsize = :erlang.system_info(:wordsize)

    ets_bytes =
      :persistent_term.get(:cache_tables, [])
      |> Enum.reduce(0, fn table, acc ->
        case :ets.info(table, :memory) do
          :undefined -> acc
          words -> acc + words * wordsize
        end
      end)

    nebulex_bytes =
      [NebulexLocalCache, NebulexCoherentCache]
      |> Enum.reduce(0, fn cache, acc ->
        case cache.info(:memory) do
          {:ok, %{used: used}} when is_integer(used) -> acc + used
          _ -> acc
        end
      end)

    ets_bytes + nebulex_bytes
  end

  @doc """
  Snapshot ETS tables owned by cache processes started after `tables_before`.

  Call before starting cache processes:
      tables_before = :ets.all() |> MapSet.new()

  Then after starting:
      BenchmarkHelpers.init_cache_tables(tables_before)
  """
  def init_cache_tables(tables_before) do
    bonfire_cache_table =
      case :ets.info(:bonfire_cache, :name) do
        :undefined -> []
        _ -> [:bonfire_cache]
      end

    cache_tables =
      :ets.all()
      |> MapSet.new()
      |> MapSet.difference(tables_before)
      |> MapSet.to_list()
      |> Kernel.++(bonfire_cache_table)

    :persistent_term.put(:cache_tables, cache_tables)
  end

  # ---------------------------------------------------------------------------
  # Scenario hooks for ETS delta tracking
  # ---------------------------------------------------------------------------

  @doc """
  Wrap a scenario map so each scenario fn automatically records its name for ETS delta tracking.
  Pass your raw `%{name => fun}` map and get back the same map with name-recording injected.
  """
  def wrap_scenarios(scenarios) do
    Enum.into(scenarios, %{}, fn
      {name, {fun, hooks}} when is_function(fun) and is_list(hooks) ->
        wrapped = fn input ->
          record_scenario_name(name)
          fun.(input)
        end

        {name, {wrapped, hooks}}

      {name, fun} ->
        {name,
         fn input ->
           record_scenario_name(name)
           fun.(input)
         end}
    end)
  end

  @doc "Stop a list of GenServer pids and optionally remove temp directories."
  def cleanup(pids, paths \\ []) do
    Enum.each(pids, &GenServer.stop/1)
    Enum.each(paths, &File.rm_rf!/1)
  end

  @doc "Snapshot current cache memory usage and record input name for ETS delta tracking. Call after flushing and warming, just before the benchmark iterations."
  def snapshot_mem(input_name \\ nil) do
    :persistent_term.put(:bench_results, :persistent_term.get(:bench_results, %{}))
    if input_name, do: Process.put(:bench_input_name, input_name)
    Process.put(:bench_cache_mem_before, cache_mem())
  end

  @doc "Call at the start of each scenario fn to record the scenario name."
  def record_scenario_name(name) do
    Process.put(:bench_scenario_name, name)
  end

  @doc "Call in `after_scenario` to store the ETS delta for the current scenario."
  def after_scenario(input_name \\ nil) do
    scenario = Process.get(:bench_scenario_name, "unknown")
    input = input_name || Process.get(:bench_input_name, "unknown")
    mem_before = Process.get(:bench_cache_mem_before, 0)
    delta = cache_mem() - mem_before
    results = :persistent_term.get(:bench_results, %{})
    :persistent_term.put(:bench_results, Map.put(results, {scenario, input}, delta))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Byte formatting
  # ---------------------------------------------------------------------------

  def format_bytes(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 2)} MB"
  def format_bytes(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)} KB"
  def format_bytes(n), do: "#{n} B"

  # ---------------------------------------------------------------------------
  # Benchee.Formatter — ETS size delta report
  # ---------------------------------------------------------------------------

  @impl true
  def format(%{scenarios: scenarios}, _options) do
    lines =
      Enum.flat_map(scenarios, fn scenario ->
        name = scenario.name
        input_name = scenario.input_name
        results = :persistent_term.get(:bench_results, %{})

        case Map.fetch(results, {name, input_name}) do
          :error ->
            []

          {:ok, delta} ->
            sign = if delta >= 0, do: "+", else: ""

            [
              "  #{name} (#{input_name})\n" <>
                "    ETS size Δ: #{sign}#{format_bytes(delta)}"
            ]
        end
      end)

    "\n=== ETS Size Change per Scenario ===\n" <> Enum.join(lines, "\n") <> "\n"
  end

  @impl true
  def write(output, _options) do
    IO.puts(output)
    :ok
  end
end
