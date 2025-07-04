defmodule Bonfire.Common.Testing do
  use Bonfire.Common.Config

  def configure_start_test(opts \\ [migrate: false]) do
    running_a_second_test_instance? = System.get_env("TEST_INSTANCE") == "yes"

    # Start ExUnitSummary application, with recommended config 
    # ExUnitSummary.start(:normal, %ExUnitSummary.Config{
    #   filter_results: :success, 
    #   # filter_results: :failed, 
    #   print_delay: 100
    #   })

    ExUnit.configure(
      # please note that Mneme overrides any custom formatters
      formatters: Bonfire.Common.RuntimeConfig.test_formatters(),
      #  miliseconds
      timeout: 120_000,
      assert_receive_timeout: 1000,
      exclude: Bonfire.Common.RuntimeConfig.skip_test_tags(),
      # only show log for failed tests (Can be overridden for individual tests via `@tag capture_log: false`)
      capture_log:
        !running_a_second_test_instance? and System.get_env("CAPTURE_LOG") != "no" and
          System.get_env("UNTANGLE_TO_IO") != "yes"
    )

    # ExUnit.configuration()
    # |> IO.inspect()

    # Code.put_compiler_option(:nowarn_unused_vars, true)

    ExUnit.start()
    Repatch.setup()

    if System.get_env("TEST_WITH_MNEME") != "no",
      do: Mneme.start(),
      else: Mneme.Options.configure([])

    repo = Bonfire.Common.Config.repo()

    if repo do
      try do
        if opts[:migrate] do
          Mix.Task.run("ecto.create")
          Mix.Task.run("ecto.migrate")
          EctoSparkles.Migrator.migrate(repo)
        end

        # Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)

        # if System.get_env("PHX_SERVER") !="yes" do
        Ecto.Adapters.SQL.Sandbox.mode(repo, :auto)
        # end

        # insert fixtures in test instance's repo on startup
        if running_a_second_test_instance?,
          do:
            Bonfire.Common.TestInstanceRepo.apply(fn ->
              nil
              # EctoSparkles.Migrator.migrate(Bonfire.Common.TestInstanceRepo)
            end)
      rescue
        e in RuntimeError ->
          IO.warn("Could not set up database")
          IO.inspect(e)
      end
    end

    # ExUnit.after_suite(fn results ->
    #     # do stuff
    #     IO.inspect(test_results: results)

    #     :ok
    # end)

    try do
      Application.put_env(:wallaby, :base_url, Bonfire.Web.Endpoint.url())
      chromedriver_path = Bonfire.Common.Config.get([:wallaby, :chromedriver, :path])

      if chromedriver_path && File.exists?(chromedriver_path),
        do: {:ok, _} = Application.ensure_all_started(:wallaby),
        else:
          IO.inspect("Note: Wallaby UI tests will not run because the chromedriver is missing")
    rescue
      e in RuntimeError ->
        IO.warn("Could not set up Wallaby UI tests ")
        IO.inspect(e)
    end

    IO.puts("""

    Testing shows the presence, not the absence of bugs.
     - Edsger W. Dijkstra
    """)

    if System.get_env("OBSERVE") do
      Bonfire.Application.observer()
    end

    # ExUnit.configuration()
    # |> IO.inspect()

    :ok
  end
end
