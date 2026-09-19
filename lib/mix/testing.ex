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
      # max_cases: 10,
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
          EctoSparkles.Migrator.migrate_repo(repo, continue_on_error: true)
        end

        # Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)

        # if System.get_env("PHX_SERVER") !="yes" do
        Ecto.Adapters.SQL.Sandbox.mode(repo, :auto)
        # end

        # insert fixtures in test instance's repo on startup
        if running_a_second_test_instance?,
          do:
            Bonfire.Common.TestInstanceRepo.apply(fn ->
              EctoSparkles.Migrator.migrate_repo(Bonfire.Common.TestInstanceRepo,
                continue_on_error: true
              )

              # nil
            end)
      rescue
        e in RuntimeError ->
          IO.warn("Could not set up test database")
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

  @doc """
  Runs a function and counts the database queries it made, returning `{result, count}`.

  For a test that has to pin work as batched: assert the count stays the same as the number of
  records grows, and an N+1 reintroduced later fails the test rather than only showing up as
  slowness in production.

  Counts queries made in the calling process only, since telemetry handlers are global and a
  LiveView or a `Task` running alongside would otherwise be counted too.

      {targets, queries} = count_queries(fn -> FanOut.targets(recipients, activity) end)
      assert queries == 2
  """
  def count_queries(fun) when is_function(fun, 0) do
    repo = Bonfire.Common.Config.repo()
    event = repo.config()[:telemetry_prefix] ++ [:query]
    counting_for = self()
    handler_id = {__MODULE__, :count_queries, make_ref()}

    :telemetry.attach(
      handler_id,
      event,
      fn _event, _measurements, _metadata, _config ->
        if self() == counting_for, do: send(counting_for, {handler_id, :query})
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain_query_count(handler_id, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_query_count(handler_id, count) do
    receive do
      {^handler_id, :query} -> drain_query_count(handler_id, count + 1)
    after
      0 -> count
    end
  end
end
