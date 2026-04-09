defmodule Bonfire.Common.Cache.CacheBackendBenchmark do
  @moduledoc """
  Benchmark comparing cache backends for latency and memory footprint:

  - **Bonfire.Common.Cache** — default Cachex-backed cache
  - **Cachex direct** — raw Cachex API
  # - **Nebulex with Cachex** — Nebulex Cachex Adapter
  - **Nebulex Local** — `Nebulex.Adapters.Local` (ETS)
  - **Nebulex Coherent** — `Nebulex.Adapters.Coherent` (local + cluster invalidations)
  - **Nebulex DiskLFU** — disk-only with LFU eviction
  # - **Bonfire LocalDiskAdapter** — ETF files via `Cachex.Disk`

  Run from IEx:

      Bonfire.Common.Cache.CacheBackendBenchmark.run()

  Results are written to `cache_benchmark_results.html`.
  """

  alias Bonfire.Common.Cache.DiskLFUCache
  alias Bonfire.Common.Cache.NebulexLocalCache
  alias Bonfire.Common.Cache.NebulexCoherentCache
  alias Bonfire.Common.Cache.BenchmarkHelpers
  # alias Bonfire.Common.Cache.LocalDiskCache

  @cachex_name :bench_cachex
  @preloaded_key "bench:preloaded"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def run do
    Logger.configure(level: :error)
    :persistent_term.put(:bench_results, %{})

    tmp = System.tmp_dir!()
    disk_path = Path.join(tmp, "bonfire_bench_disk_#{:os.getpid()}")
    lfu_path = Path.join(tmp, "bonfire_bench_lfu_#{:os.getpid()}")

    File.mkdir_p!(disk_path)
    File.mkdir_p!(lfu_path)

    tables_before = :ets.all() |> MapSet.new()

    {:ok, cachex_pid} = Cachex.start_link(@cachex_name, [])
    {:ok, local_pid} = NebulexLocalCache.start_link([])
    {:ok, coherent_pid} = NebulexCoherentCache.start_link([])
    # {:ok, disk_pid} = DiskCache.start_link(root_path: disk_path)
    {:ok, lfu_pid} = DiskLFUCache.start_link(root_path: lfu_path, max_bytes: nil)

    BenchmarkHelpers.init_cache_tables(tables_before)

    inputs = build_inputs()

    results =
      Benchee.run(
        scenarios(),
        inputs: inputs,
        time: 5,
        warmup: 2,
        memory_time: 2,
        before_scenario: fn input ->
          # Flush all caches so ETS delta reflects only this scenario's writes,
          # not entries written + janitor-evicted from the previous scenario
          BenchmarkHelpers.flush_all()
          Cachex.clear(@cachex_name)
          # Pre/re-populate preloaded keys for get-hit scenarios (cleared above)
          Bonfire.Common.Cache.put(@preloaded_key, input)
          Cachex.put(@cachex_name, @preloaded_key, input)
          NebulexLocalCache.put!(@preloaded_key, input)
          NebulexCoherentCache.put!(@preloaded_key, input)
          DiskLFUCache.put!(@preloaded_key, if(is_binary(input), do: input, else: :erlang.term_to_binary(input)))
          BenchmarkHelpers.snapshot_mem()
          input
        end,

        after_scenario: fn _input ->
          BenchmarkHelpers.after_scenario()
        end,
        print: [fast_warning: false],
        formatters: [
          Benchee.Formatters.Console,
          BenchmarkHelpers,
          {Benchee.Formatters.HTML, file: "cache_benchmark_results.html", auto_open: true}
        ]
      )

    BenchmarkHelpers.cleanup(
      [cachex_pid, local_pid, coherent_pid, lfu_pid],
      [disk_path, lfu_path]
    )

    results
  end

  # ---------------------------------------------------------------------------
  # Benchmark scenarios
  # ---------------------------------------------------------------------------

  defp scenarios, do: BenchmarkHelpers.wrap_scenarios(the_scenarios())

  defp the_scenarios do
    counter = :counters.new(1, [])

    unique_key = fn prefix ->
      n = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      "#{prefix}:#{n}"
    end

    %{
      # --- Cachex via Bonfire.Common.Cache (default) ---
      "bonfire cache put" => fn v ->
        Bonfire.Common.Cache.put(unique_key.("bc"), v)
      end,
      "bonfire cache get hit" => fn _v ->
        Bonfire.Common.Cache.get!(@preloaded_key)
      end,
      "bonfire cache get miss" => fn _v ->
        Bonfire.Common.Cache.get!(unique_key.("bc_miss"))
      end,

      # --- Cachex direct ---
      "cachex put" => fn v ->
        Cachex.put(@cachex_name, unique_key.("cx"), v)
      end,
      "cachex get hit" => fn _v ->
        Cachex.get(@cachex_name, @preloaded_key)
      end,
      "cachex get miss" => fn _v ->
        Cachex.get(@cachex_name, unique_key.("cx_miss"))
      end,

      # --- Nebulex Local (ETS) ---
      "nebulex local put" => fn v ->
        NebulexLocalCache.put!(unique_key.("nl"), v)
      end,
      "nebulex local get hit" => fn _v ->
        NebulexLocalCache.get!(@preloaded_key)
      end,
      "nebulex local get miss" => fn _v ->
        NebulexLocalCache.get!(unique_key.("nl_miss"))
      end,

      # --- Nebulex Coherent (local + cluster invalidations) ---
      "nebulex coherent put" => fn v ->
        NebulexCoherentCache.put!(unique_key.("nc"), v)
      end,
      "nebulex coherent get hit" => fn _v ->
        NebulexCoherentCache.get!(@preloaded_key)
      end,
      "nebulex coherent get miss" => fn _v ->
        NebulexCoherentCache.get!(unique_key.("nc_miss"))
      end,

      # # --- Nebulex DiskAdapter (ETF files) ---
      # "disk put" => fn v ->
      #   DiskCache.put!(unique_key.("dk"), v)
      # end,
      # "disk get hit" => fn _v ->
      #   DiskCache.get!(@preloaded_key)
      # end,
      # "disk get miss" => fn _v ->
      #   DiskCache.get!(unique_key.("dk_miss"))
      # end,

      # --- Nebulex DiskLFU ---
      "lfu put" => fn v ->
        if is_binary(v) do
          DiskLFUCache.put!(unique_key.("lfu"), v)
        else
          DiskLFUCache.put!(unique_key.("lfu"), :erlang.term_to_binary(v))
        end
      end,
      "lfu get hit" => fn v ->
        result = DiskLFUCache.get!(@preloaded_key)
        if is_binary(v) or is_nil(result), do: result, else: :erlang.binary_to_term(result)
      end,
      "lfu get miss" => fn _v ->
        DiskLFUCache.get!(unique_key.("lfu_miss"))
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Inputs
  # ---------------------------------------------------------------------------

  defp build_inputs do
    %{
      "simple (string: binary instead of erlang term)" => "Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?",
      "small (boolean flag)" => true,
      "medium (user map ~1KB)" => medium_value(),
      "large (activity list ~50KB)" => large_value()
    }
  end

  defp medium_value do
    %{
      id: "01GNDR2XXXXXXXXXXXXXXXXXX1",
      name: "Alice Example",
      username: "alice",
      email: "alice@example.com",
      bio: String.duplicate("A bonfire user bio. ", 10),
      profile: %{
        icon_url: "https://example.com/avatar.png",
        banner_url: "https://example.com/banner.png",
        website: "https://alice.example.com",
        location: "The Internet",
        pronouns: "they/them"
      },
      settings: %{theme: "dark", language: "en", notifications: true},
      inserted_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-06-01 00:00:00Z]
    }
  end

  defp large_value do
    Enum.map(1..50, fn i ->
      %{
        id: "01GNDR2XXXXXXXXXXXXX#{String.pad_leading(to_string(i), 5, "0")}",
        verb: "Create",
        object: %{
          id: "01GNDR3XXXXXXXXXXXXX#{String.pad_leading(to_string(i), 5, "0")}",
          content: String.duplicate("Activity object content for item #{i}. ", 8),
          tags: ["bonfire", "elixir", "fediverse"],
          inserted_at: ~U[2024-01-01 00:00:00Z]
        },
        actor: %{
          id: "01GNDR4XXXXXXXXXXXXX#{String.pad_leading(to_string(i), 5, "0")}",
          name: "User #{i}",
          username: "user_#{i}",
          ap_id: "https://example.com/users/user_#{i}"
        },
        inserted_at: ~U[2024-01-01 00:00:00Z]
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Memory helpers
  # ---------------------------------------------------------------------------

  defp identify_input(v) when is_boolean(v), do: "small (boolean flag)"
  defp identify_input(v) when is_binary(v), do: "simple (string: binary instead of erlang term)"
  defp identify_input(v) when is_map(v), do: "medium (user map ~1KB)"
  defp identify_input(v) when is_list(v), do: "large (activity list ~50KB)"
  defp identify_input(_), do: "unknown"


end
