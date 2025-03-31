defmodule Bonfire.Common.RuntimeConfig do
  @moduledoc "Config and helpers for this library"

  import Untangle

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  def config do
    import Config

    config :bonfire_common,
      root_path: File.cwd!()

    yes? = ~w(true yes 1)
    no? = ~w(false no 0)

    test_instance = System.get_env("TEST_INSTANCE")

    repo_app =
      Bonfire.Common.Config.get(:umbrella_otp_app) || Bonfire.Common.Config.get(:otp_app) ||
        :bonfire_common

    repos =
      if Code.ensure_loaded?(Beacon.Repo),
        do: [Bonfire.Common.Repo, Beacon.Repo],
        else: [Bonfire.Common.Repo]

    repos =
      if test_instance in yes?,
        do: repos ++ [Bonfire.Common.TestInstanceRepo],
        else: repos

    db_url = System.get_env("DATABASE_URL") || System.get_env("CLOUDRON_POSTGRESQL_URL")
    db_pw = System.get_env("POSTGRES_PASSWORD") || System.get_env("CLOUDRON_POSTGRESQL_PASSWORD")

    db_url || db_pw ||
      System.get_env("MIX_QUIET") ||
      error("""
      Environment variables for database are missing.
      For example: DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
      You can also set POSTGRES_PASSWORD (required),
      and POSTGRES_USER (default: postgres) and POSTGRES_HOST (default: localhost)
      """)

    maybe_repo_ipv6 = if System.get_env("ECTO_IPV6") in yes?, do: [:inet6], else: []

    repo_connection_config =
      if db_url do
        [
          url: db_url,
          socket_options: maybe_repo_ipv6
        ]
      else
        [
          username:
            System.get_env("POSTGRES_USER") ||
              System.get_env("CLOUDRON_POSTGRESQL_USERNAME", "postgres"),
          password: db_pw || "postgres",
          hostname:
            System.get_env("POSTGRES_HOST") ||
              System.get_env("CLOUDRON_POSTGRESQL_HOST", "localhost"),
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

        # default to twice the number of CPU cores
        _ ->
          System.schedulers_online() * 2
      end

    IO.puts("Note: Starting database connection pool of #{pool_size}")

    config repo_app, ecto_repos: repos
    config :paginator, ecto_repos: repos
    config :activity_pub, ecto_repos: repos

    config repo_app, Bonfire.Common.Repo, repo_connection_config
    config repo_app, Bonfire.Common.TestInstanceRepo, repo_connection_config
    config :beacon, Beacon.Repo, repo_connection_config

    config repo_app, Bonfire.Common.Repo, database: database
    config :beacon, Beacon.Repo, database: database
    config :paginator, Paginator.Repo, database: database

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
        # log: :info,
        log: false,
        stacktrace: true

      config :paginator, Paginator.Repo,
        pool: Ecto.Adapters.SQL.Sandbox,
        username: System.get_env("POSTGRES_USER", "postgres"),
        password: System.get_env("POSTGRES_PASSWORD", "postgres"),
        hostname: System.get_env("POSTGRES_HOST", "localhost")

      # use Ecto sandbox?
      config :bonfire_common,
        sql_sandbox:
          System.get_env("PHX_SERVER") != "yes" and System.get_env("TEST_INSTANCE") != "yes"
    end

    config :bonfire, :http,
      proxy_url: System.get_env("HTTP_PROXY_URL"),
      adapter_options: [
        ssl_options: [
          # Workaround for remote server certificate chain issues
          # partial_chain: &:hackney_connect.partial_chain/1,
          # We don't support TLS v1.3 yet
          versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"]
        ]
      ]

    config :bonfire_common, Bonfire.Common.Localise.Cldr, locales: Cldr.all_locale_names()

    config :bonfire_common, Bonfire.Common.AntiSpam.Akismet,
      api_key: System.get_env("AKISMET_API_KEY")
  end

  def skip_test_tags(extras \\ []) do
    chromedriver_path = Bonfire.Common.Config.get([:wallaby, :chromedriver, :path])

    # TODO: less ugly
    skip = extras ++ [:skip, :todo, :fixme, :benchmark, :live_federation]

    # skip two-instances-required federation tests
    skip =
      if System.get_env("TEST_INSTANCE") == "yes",
        do: skip,
        else: [:test_instance] ++ skip

    # tests to skip in CI env
    skip = if System.get_env("CI"), do: [:skip_ci] ++ skip, else: skip

    skip = if System.get_env("TEST_WITH_MNEME") == "no", do: [:mneme] ++ skip, else: skip

    # skip browser automation tests in CI
    skip =
      if System.get_env("CI") || is_nil(chromedriver_path),
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
