defmodule Bonfire.Common.RuntimeConfig do
  @moduledoc "Config and helpers for this library"

  import Untangle
  require Bonfire.Common.Config
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @yes? ~w(true yes 1)
  @no? ~w(false no none 0)

  def config do
    import Config

    config :bonfire_common,
      root_path: File.cwd!()

    test_instance = System.get_env("TEST_INSTANCE")

    repo_app =
      Bonfire.Common.Config.get(:umbrella_otp_app) || Bonfire.Common.Config.get(:otp_app) ||
        :bonfire_common

    repos =
      if Code.ensure_loaded?(Beacon.Repo),
        do: [Bonfire.Common.Repo, Beacon.Repo],
        else: [Bonfire.Common.Repo]

    repos =
      if test_instance in @yes?,
        do: repos ++ [Bonfire.Common.TestInstanceRepo],
        else: repos

    db_url =
      Bonfire.Common.EnvSecrets.env_or_file("DATABASE_URL") ||
        Bonfire.Common.EnvSecrets.env_or_file("CLOUDRON_POSTGRESQL_URL")

    pg_username =
      System.get_env("POSTGRES_USER") ||
        System.get_env("CLOUDRON_POSTGRESQL_USERNAME", "postgres")

    pg_host =
      System.get_env("POSTGRES_HOST") ||
        System.get_env("CLOUDRON_POSTGRESQL_HOST", "localhost")

    pg_pw =
      Bonfire.Common.EnvSecrets.env_or_file("POSTGRES_PASSWORD") ||
        Bonfire.Common.EnvSecrets.env_or_file("CLOUDRON_POSTGRESQL_PASSWORD")

    db_url || pg_pw ||
      System.get_env("MIX_QUIET") ||
      error("""
      Environment variables for database are missing.
      For example: DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
      You can also set POSTGRES_PASSWORD (required),
      and POSTGRES_USER (default: postgres) and POSTGRES_HOST (default: localhost)
      """)

    maybe_repo_ipv6 = if System.get_env("ECTO_IPV6") in @yes?, do: [:inet6], else: []

    repo_connection_config =
      if db_url do
        [
          url: db_url,
          socket_options: maybe_repo_ipv6
        ]
      else
        [
          username: pg_username,
          password: pg_pw || "postgres",
          hostname: pg_host,
          socket_options: maybe_repo_ipv6
        ]
      end

    database =
      case config_env() do
        :test ->
          "bonfire_test_#{test_instance}_#{System.get_env("MIX_TEST_PARTITION") || 0}"

        :dev ->
          System.get_env("POSTGRES_DB", "bonfire_dev")

        _ ->
          System.get_env("POSTGRES_DB") || System.get_env("CLOUDRON_POSTGRESQL_DATABASE") ||
            "bonfire"
      end

    pool_size =
      case System.get_env("POOL_SIZE") do
        pool when is_binary(pool) and pool not in ["", "0"] ->
          String.to_integer(pool)

        # Default to twice the number of CPU cores, with minimum safe sizes.
        # Minimum pool size should account for:
        # - Oban workers (~18 by default for federation queues)
        # - Web requests (varies)
        # - LiveView connections (varies)
        _ ->
          base_size = System.schedulers_online() * 2
          min_safe_size = 25
          if config_env() == :test, do: max(base_size, 20), else: max(base_size, min_safe_size)
      end

    #  use lighter advisory locks for migrations, allowing concurrent indexing?
    migration_lock =
      if System.get_env("DB_MIGRATE_INDEXES_CONCURRENTLY") != "false",
        do: :pg_advisory_lock,
        else: :table_lock

    IO.puts(
      "Note: Starting database connection pool of #{pool_size} with #{migration_lock} migration lock for #{database}"
    )

    config repo_app, ecto_repos: repos
    config :paginator, ecto_repos: repos
    config :activity_pub, ecto_repos: repos

    config repo_app, Bonfire.Common.Repo, repo_connection_config
    config repo_app, Bonfire.Common.TestInstanceRepo, repo_connection_config
    config :beacon, Beacon.Repo, repo_connection_config

    config repo_app, Bonfire.Common.Repo, database: database
    config :beacon, Beacon.Repo, database: database
    config :paginator, Paginator.Repo, database: database

    config repo_app, Bonfire.Common.Repo, migration_lock: migration_lock
    config repo_app, Bonfire.Common.TestInstanceRepo, migration_lock: migration_lock

    config repo_app, Bonfire.Common.Repo, pool_size: pool_size
    config repo_app, Bonfire.Common.TestInstanceRepo, pool_size: pool_size
    config :beacon, Beacon.Repo, pool_size: pool_size
    config :paginator, Paginator.Repo, pool_size: pool_size

    repo_path = System.get_env("DB_REPO_PATH", "priv/repo")
    config repo_app, Bonfire.Common.Repo, priv: repo_path
    config repo_app, Bonfire.Common.Repo, priv: repo_path
    config repo_app, Bonfire.Common.TestInstanceRepo, priv: repo_path

    config :ecto_sparkles,
      slow_query_ms: String.to_integer(System.get_env("DB_SLOW_QUERY_MS", "100")),
      queries_log_level: String.to_atom(System.get_env("DB_QUERIES_LOG_LEVEL", "debug"))

    if config_env() == :test do
      # Configure your test database
      # db = "bonfire_test#{System.get_env("MIX_TEST_PARTITION") || 0}"
      #
      # The MIX_TEST_PARTITION environment variable can be used
      # to provide built-in test partitioning in CI environment.
      # Run `mix help test` for more information.
      config repo_app, Bonfire.Common.Repo,
        pool: Ecto.Adapters.SQL.Sandbox,
        # show_sensitive_data_on_connection_error: true,
        # database: db,
        slow_query_ms: 500,
        queue_target: 5_000,
        queue_interval: 2_000,
        timeout: 50_000,
        connect_timeout: 10_000,
        ownership_timeout: 100_000,
        # Increase pool size for CI to handle concurrent tests - force minimum of 20 for tests
        pool_size: max(pool_size, 20),
        log: false,
        stacktrace: true

      config :paginator, Paginator.Repo,
        pool: Ecto.Adapters.SQL.Sandbox,
        username: pg_username,
        password: pg_pw,
        hostname: pg_host
    end

    config :sql,
      pools: [
        default: %{
          username: pg_username,
          password: pg_pw,
          hostname: pg_host,
          database: database,
          adapter: SQL.Adapters.Postgres,
          repo: Bonfire.Common.Repo,
          ssl: false
        }
      ]

    config :bonfire, :http,
      proxy_url: System.get_env("HTTP_PROXY_URL"),
      adapter_options: [
        ssl_options: [
          verify: :verify_peer,
          # Workaround for remote server certificate chain issues
          # partial_chain: &:hackney_connect.partial_chain/1,
          # Some servers don't support TLS v1.3 yet so we disable it for compatibility
          versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"]
        ]
      ]

    config :bonfire_common, Bonfire.Common.Localise.Cldr, locales: :all

    config :bonfire_common, Bonfire.Common.AntiSpam.Akismet,
      api_key: Bonfire.Common.EnvSecrets.env_or_file("AKISMET_API_KEY")

    # Oban throughput presets (#1638) — admin-switchable multipliers over the configured queue sizes.
    # `:default` (the env baseline) and `:custom` (per-queue overrides) are built-in; the rest scale
    # every managed queue's limit by their factor. `cards` is the per-preset UI metadata (here, since
    # this module has `l()` for i18n, unlike `config/runtime.exs`).
    config :bonfire_common, Bonfire.Common.ObanPresets,
      preset_names: [:eco, :default, :turbo, :custom],
      multipliers: [eco: 0.5, turbo: 2.0],
      cards: [
        eco: [
          icon: "ph:leaf-duotone",
          name: l("Eco"),
          description:
            l(
              "Gentler on the server (half the default concurrency). Good for small or shared hosting."
            )
        ],
        default: [
          icon: "ph:gauge-duotone",
          name: l("Default"),
          description: l("As configured by server admins, your app flavour, or developers.")
        ],
        turbo: [
          icon: "ph:rocket-launch-duotone",
          name: l("Turbo"),
          description:
            l("Double the concurrency for faster federation and such on capable servers.")
        ],
        custom: [
          icon: "ph:sliders-horizontal-duotone",
          name: l("Custom"),
          description: l("Fine-tune individual queue concurrency.")
        ]
      ],
      # Human labels for known queues (advanced editor rows; unknown queues fall back to the
      # technical name, which always shows in the row tooltip)
      queue_labels: [
        federator_incoming: l("Incoming activities"),
        federator_incoming_unverified: l("Incoming activities (unverified)"),
        federator_incoming_mentions: l("Incoming mentions & messages"),
        federator_incoming_follows: l("Incoming follows"),
        federator_outgoing: l("Outgoing deliveries"),
        remote_fetcher: l("Fetching remote content"),
        import: l("Data Imports"),
        deletion: l("Data Deletions"),
        database_prune: l("Database pruning"),
        static_generator: l("Static page generation"),
        fetch_open_science: l("Open science sync"),
        ghost_webhooks: l("Ghost webhooks"),
        search_index: l("Search indexing")
      ],
      # Quick per-group boost toggles (Layer 2): toggling one runs that group of federation queues
      # at double concurrency (the `turbo` level), on top of whatever preset is active.
      groups: [
        interactions: [
          name: l("Mentions & follows"),
          description: l("Keep incoming messages, mentions and follow requests snappy."),
          queues: [:federator_incoming_mentions, :federator_incoming_follows]
        ],
        incoming: [
          name: l("Incoming"),
          description: l("See remote activities appear faster in feeds."),
          queues: [:federator_incoming]
        ],
        outgoing: [
          name: l("Outgoing delivery"),
          description: l("Sending local activities out to the fediverse."),
          queues: [:federator_outgoing]
        ]
      ]

    # Instance performance tuning (calm-empowerment over the Postgres layer; see
    # `Bonfire.Common.Settings.Calm.InstanceTuning` + plans/postgres-ops-tuning.md › C2).
    # Presets/toggles are TRANSFORMS over the boot baseline (a pg_settings snapshot) — boot config
    # stays the single source of truth; values are typed + clamped, applied via whitelisted
    # ALTER SYSTEM + pg_reload_conf. NOTE bounds/tiers are in each GUC's base unit (work_mem: kB).
    # Enum-typed GUCs (wal_compression, default_toast_compression) await an :enum knob type.
    config :bonfire_common, Bonfire.Common.Settings.Calm.InstanceTuning,
      preset_names: [:eco, :default, :turbo, :custom],
      cards: [
        eco: [
          icon: "ph:leaf-duotone",
          name: l("Eco"),
          description: l("Leave headroom for other services sharing this machine.")
        ],
        default: [
          icon: "ph:gauge-duotone",
          name: l("Default"),
          description: l("The default configuration.")
        ],
        turbo: [
          icon: "ph:rocket-launch-duotone",
          name: l("Turbo"),
          description: l("This machine is for Bonfire: favor speed.")
        ],
        custom: [
          icon: "ph:sliders-horizontal-duotone",
          name: l("Custom"),
          description: l("Manually adjust individual settings.")
        ]
      ],
      # Level 1: per-knob transforms over the baseline (only deviations listed)
      presets: [
        eco: [
          work_mem: {:scale, 0.5},
          maintenance_work_mem: {:scale, 0.5},
          log_min_duration_statement: {:set, 5_000},
          lv_hibernate_after: {:set, 3_000},
          app_log_level: {:set, :warning}
        ],
        turbo: [
          work_mem: {:scale, 2.0},
          maintenance_work_mem: {:scale, 2.0},
          autovacuum_vacuum_cost_limit: {:set, 2_000},
          autovacuum_vacuum_cost_delay: {:set, 2.0},
          track_io_timing: {:set, "on"},
          log_min_duration_statement: {:set, 2_000},
          lv_hibernate_after: {:set, 15_000}
        ]
      ],
      # Level 2: outcome-named override toggles (each bundles a few knob transforms)
      groups: [
        faster_feeds: [
          name: l("Faster feeds & threads"),
          description: l("Give queries more memory to sort with."),
          knobs: [work_mem: {:step, 1}, log_temp_files: {:set, 0}]
        ],
        lean_database: [
          name: l("Keep the database lean"),
          description:
            l("Clean up more aggressively (good for busy or bulk-importing instances)."),
          knobs: [
            autovacuum_vacuum_cost_limit: {:set, 2_000},
            autovacuum_vacuum_insert_scale_factor: {:set, 0.02},
            autovacuum_naptime: {:set, 30}
          ]
        ],
        diagnostics: [
          name: l("Deep diagnostics"),
          description:
            l(
              "Log slow queries and I/O details (small overhead, enable when things feel slow and you want to investigate)."
            ),
          knobs: [
            log_min_duration_statement: {:set, 2_000},
            track_io_timing: {:set, "on"},
            log_lock_waits: {:set, "on"},
            n_plus_1_detect: {:set, "on"}
          ]
        ],
        quiet_logs: [
          name: l("Quiet logs"),
          description: l("Only log warnings, errors, and unusually slow things."),
          knobs: [
            log_min_duration_statement: {:set, -1},
            log_autovacuum_min_duration: {:set, 10_000},
            app_log_level: {:set, :warning}
          ]
        ]
      ],
      # Level 3: the knob registry (context :user/:sighup = live on reload; :postmaster would need
      # a restart badge — none included yet). `unit:` is the HUMAN unit all our numbers use
      # (bounds/tiers/presets/UI); the applier emits pg unit-suffixed literals and converts the
      # pg-native units back on baseline read. `name:` is the admin-facing label (the technical
      # GUC name shows in a tooltip).
      knob_registry: [
        work_mem: [
          name: l("Query working memory"),
          layer: :postgres,
          context: :user,
          type: :int,
          unit: "MB",
          bounds: {4, 2_048},
          tiers: [16, 32, 64, 128, 256],
          # admin overrides stored as % of the tuner's baseline (slider UI) — recomputes on resize
          relative: true
        ],
        maintenance_work_mem: [
          name: l("Maintenance memory"),
          layer: :postgres,
          context: :user,
          type: :int,
          unit: "MB",
          bounds: {16, 4_096},
          relative: true
        ],
        effective_cache_size: [
          name: l("Assumed OS cache size (query planner)"),
          layer: :postgres,
          context: :user,
          type: :int,
          unit: "MB",
          bounds: {256, 65_536},
          relative: true
        ],
        effective_io_concurrency: [
          name: l("Concurrent disk reads"),
          layer: :postgres,
          context: :user,
          type: :int,
          bounds: {0, 512}
        ],
        max_parallel_workers_per_gather: [
          name: l("Parallel workers per query"),
          layer: :postgres,
          context: :user,
          type: :int,
          bounds: {0, 16},
          # CPU-scaled by the tuner → admin overrides stored as % of baseline
          relative: true
        ],
        max_parallel_workers: [
          name: l("Parallel workers (total)"),
          layer: :postgres,
          context: :sighup,
          type: :int,
          bounds: {0, 64},
          relative: true
        ],
        max_parallel_maintenance_workers: [
          name: l("Parallel maintenance workers"),
          layer: :postgres,
          context: :user,
          type: :int,
          bounds: {0, 16},
          relative: true
        ],
        default_statistics_target: [
          name: l("Planner statistics detail"),
          layer: :postgres,
          context: :user,
          type: :int,
          bounds: {10, 10_000}
        ],
        random_page_cost: [
          name: l("Random read cost (query planner)"),
          layer: :postgres,
          context: :user,
          type: :real
        ],
        jit: [name: l("JIT query compilation"), layer: :postgres, context: :user, type: :bool],
        track_io_timing: [
          name: l("Track I/O timing"),
          layer: :postgres,
          context: :user,
          type: :bool
        ],
        log_min_duration_statement: [
          name: l("Log queries slower than"),
          layer: :postgres,
          context: :user,
          type: :int,
          unit: "ms",
          bounds: {-1, 3_600_000},
          sentinels: %{-1 => l("disabled"), 0 => l("log everything")},
          # curated choices render as a labeled select — no bare -1/0 magic numbers in the UI
          choices: [
            {-1, l("disabled")},
            {100, "100 ms"},
            {500, "500 ms"},
            {1_000, "1 s"},
            {2_000, "2 s"},
            {5_000, "5 s"},
            {30_000, "30 s"}
          ]
        ],
        log_temp_files: [
          name: l("Log temp files larger than"),
          layer: :postgres,
          context: :user,
          type: :int,
          unit: "MB",
          bounds: {-1, 1_024},
          sentinels: %{-1 => l("disabled"), 0 => l("log all")},
          choices: [
            {-1, l("disabled")},
            {0, l("log all")},
            {8, "8 MB"},
            {64, "64 MB"},
            {256, "256 MB"}
          ]
        ],
        log_lock_waits: [
          name: l("Log lock waits"),
          layer: :postgres,
          context: :user,
          type: :bool
        ],
        autovacuum_vacuum_scale_factor: [
          name: l("Vacuum when dead rows exceed (fraction)"),
          layer: :postgres,
          context: :sighup,
          type: :real
        ],
        autovacuum_vacuum_insert_scale_factor: [
          name: l("Vacuum after inserts exceed (fraction)"),
          layer: :postgres,
          context: :sighup,
          type: :real
        ],
        autovacuum_analyze_scale_factor: [
          name: l("Refresh statistics when changes exceed (fraction)"),
          layer: :postgres,
          context: :sighup,
          type: :real
        ],
        autovacuum_vacuum_cost_limit: [
          name: l("Cleanup work per round"),
          layer: :postgres,
          context: :sighup,
          type: :int,
          bounds: {-1, 10_000},
          sentinels: %{-1 => l("use the global vacuum limit")},
          choices: [
            {-1, l("use the global vacuum limit")},
            {200, l("gentle (200)")},
            {1_000, l("steady (1000)")},
            {2_000, l("brisk (2000)")},
            {5_000, l("aggressive (5000)")}
          ]
        ],
        autovacuum_vacuum_cost_delay: [
          name: l("Cleanup pause between rounds"),
          layer: :postgres,
          context: :sighup,
          type: :real,
          unit: "ms"
        ],
        autovacuum_naptime: [
          name: l("Time between cleanup checks"),
          layer: :postgres,
          context: :sighup,
          type: :int,
          unit: "s",
          bounds: {1, 86_400}
        ],
        log_checkpoints: [
          name: l("Log checkpoints"),
          layer: :postgres,
          context: :sighup,
          type: :bool
        ],
        log_autovacuum_min_duration: [
          name: l("Log cleanups slower than"),
          layer: :postgres,
          context: :sighup,
          type: :int,
          unit: "ms",
          bounds: {-1, 3_600_000},
          sentinels: %{-1 => l("disabled"), 0 => l("log all")},
          choices: [
            {-1, l("disabled")},
            {0, l("log all")},
            {1_000, "1 s"},
            {10_000, "10 s"},
            {60_000, "1 min"}
          ]
        ],
        # ── Elixir layer (live via Logger.configure / app env read at call time) ──
        app_log_level: [
          name: l("App log level"),
          layer: :elixir,
          type: :enum,
          values: [:debug, :info, :warning, :error]
        ],
        ecto_slow_query_ms: [
          name: l("Log queries slower than (app-side)"),
          layer: :elixir,
          type: :int,
          unit: "ms",
          bounds: {50, 60_000}
        ],
        ecto_queries_log_level: [
          name: l("Query log level"),
          layer: :elixir,
          type: :enum,
          values: [:debug, :info, :warning]
        ],
        n_plus_1_detect: [
          name: l("Detect repeated queries (N+1)"),
          layer: :elixir,
          type: :bool
        ],
        # ── boot-time env knobs: displayed read-only with their env-var hint ──
        pool_size: [
          name: l("Database pool size"),
          layer: :elixir,
          read_only: true,
          env: "POOL_SIZE",
          repo_key: :pool_size
        ],
        db_query_timeout: [
          name: l("Query timeout"),
          layer: :elixir,
          read_only: true,
          env: "DB_QUERY_TIMEOUT",
          unit: "ms",
          repo_key: :timeout
        ],
        db_connect_timeout: [
          name: l("Database connect timeout"),
          layer: :elixir,
          read_only: true,
          env: "DB_CONNECT_TIMEOUT",
          unit: "ms",
          repo_key: :connect_timeout
        ],

        # LIVE: LV reads endpoint.config(:live_view)[:hibernate_after] from mutable ETS per mount
        # (verified in deps 2026-07-05) — new mounts pick changes up instantly, no restart
        lv_hibernate_after: [
          name: l("LiveView hibernation delay"),
          layer: :elixir,
          type: :int,
          unit: "ms",
          bounds: {1_000, 120_000},
          tiers: [3_000, 7_000, 15_000, 30_000]
        ],
        finch_connect_timeout: [
          name: l("Outbound HTTP connect timeout"),
          layer: :elixir,
          read_only: true,
          env: "FINCH_CONNECT_TIMEOUT",
          unit: "ms",
          display_default: "5000"
        ],
        # ── deploy-side Postgres tuner inputs (read by postgres-tune.sh at DB CONTAINER start —
        # the app can only display them, and only if the deploy compose passes them to the app
        # service too; changing them = edit deploy env + restart the db service) ──
        available_ram_mb: [
          name: l("RAM allotted to services (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "AVAILABLE_RAM_MB",
          unit: "MB"
        ],
        pg_ram_percent: [
          name: l("Share of RAM for the database (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "PG_RAM_PERCENT",
          unit: "%"
        ],
        cpu_count: [
          name: l("CPU cores assumed by the DB tuner (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "CPU_COUNT"
        ],
        pg_db_type: [
          name: l("Database workload profile (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "PG_DB_TYPE",
          display_default: "mixed"
        ],
        disk_storage_type: [
          name: l("Database disk type (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "DISK_STORAGE_TYPE",
          display_default: "ssd"
        ],
        pg_max_connections: [
          name: l("Max database connections (deploy)"),
          layer: :elixir,
          read_only: true,
          env: "PG_MAX_CONNECTIONS",
          display_default: "100"
        ]
      ]
  end

  def skip_test_tags(extras \\ []) do
    chromedriver_path = Bonfire.Common.Config.get([:wallaby, :chromedriver, :path])

    # TODO: less ugly
    # :fixme
    skip = extras ++ [:skip, :todo, :benchmark, :live_federation, :test_instance]

    # skip two-instances-required federation tests
    skip =
      if System.get_env("TEST_INSTANCE") == "yes",
        do: skip,
        else: [:test_instance] ++ skip

    ci? = System.get_env("CI") in @yes?
    # tests to skip in CI env
    skip = if ci?, do: [:skip_ci] ++ skip, else: skip

    skip = if System.get_env("TEST_WITH_MNEME") == "no", do: [:mneme] ++ skip, else: skip

    # skip browser automation tests in CI
    skip =
      if ci? || is_nil(chromedriver_path),
        do: [:browser] ++ skip,
        else: skip

    debug(skip, "Skipping tests tagged with")
  end

  def test_formatters(extra) do
    extra ++ test_formatters()
  end

  def test_formatters do
    [
      Bonfire.Common.TestSummary,
      ExUnit.CLIFormatter,
      ExUnitNotifier
      # ExUnitSummary.Formatter
      # Bonfire.UI.Kanban.TestDrivenCoordination
    ]
  end
end
