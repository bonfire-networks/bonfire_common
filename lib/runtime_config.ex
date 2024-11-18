defmodule Bonfire.Common.RuntimeConfig do
  @moduledoc "Config and helpers for this library"

  import Untangle

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  def config do
    import Config

    config :bonfire_common,
      root_path: File.cwd!()

    config :bonfire, :http,
      proxy_url: System.get_env("HTTP_PROXY_URL", nil),
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
