defmodule Bonfire.Common.Test.Interactive do
  @moduledoc """
  This utility allows to get the same effect of using
  `fcwatch | mix test --stale --listen-on-stdin` to watch for
  code changes and run stale tests, but with more control and
  without the starting time penalty.

  Note that watching requires fswatch on your system.
  Eg on Mac run `brew install fswatch`.

  To use it, in your project's `.iex` file add:
  ```
  unless GenServer.whereis(Bonfire.Common.Test.Interactive) do
    {:ok, pid} = Bonfire.Common.Test.Interactive.start_link()
    # Process will not exit when the iex goes out
    Process.unlink(pid)
  end
  import Bonfire.Common.Test.Interactive.Helpers
  ```
  Then to call `iex` and run tests just do:
  ```
  MIX_ENV=test iex -S mix
  ```
  The `Bonfire.Common.Test.Interactive.Helpers` allows to call `f` and `s` and `a`
  to run failed, stale and all tests respectively.
  You can call `w` to watch tests and `uw` to unwatch.
  There is a really simple throttle mecanism that disallow running the suite concurrently.
  """

  use GenServer

  defmodule Helpers do
    defdelegate ta(args \\ nil),
      to: Bonfire.Common.Test.Interactive,
      as: :run_all_tests

    defdelegate f(args \\ nil),
      to: Bonfire.Common.Test.Interactive,
      as: :run_failed_tests

    defdelegate s(args \\ nil),
      to: Bonfire.Common.Test.Interactive,
      as: :run_stale_tests

    defdelegate w(args \\ nil),
      to: Bonfire.Common.Test.Interactive,
      as: :watch_tests

    defdelegate uw, to: Bonfire.Common.Test.Interactive, as: :unwatch_tests

    def ready,
      do:
        IO.puts(
          "Test.Interactive is ready... Enter `w` to start watching for changes and `uw` to unwatch. Or run tests manually with `f` for previously-failed tests, `s` for stale ones, and `ta` to run all tests. Note that you can pass a path as argument to limit testing to specific test file(s)."
        )
  end

  defmodule Observer do
    use GenServer

    @impl true
    def init(opts) do
      {:ok, opts}
    end

    @impl true
    def handle_cast({:suite_finished, _times_us}, config) do
      Bonfire.Common.Test.Interactive.unlock()
      {:noreply, config}
    end

    @impl true
    def handle_cast(_, config) do
      {:noreply, config}
    end
  end

  def start_link do
    GenServer.start_link(__MODULE__, %{watcher: nil, lock: false}, name: __MODULE__)
  end

  def watch_tests(args) do
    GenServer.cast(__MODULE__, {:watch_tests, args})
  end

  def unwatch_tests do
    GenServer.cast(__MODULE__, :unwatch_tests)
  end

  def run_all_tests(args) do
    GenServer.call(__MODULE__, {:run, :all, args}, :infinity)
  end

  def run_failed_tests(args) do
    GenServer.call(__MODULE__, {:run, :failed, args}, :infinity)
  end

  def run_stale_tests(args) do
    GenServer.call(__MODULE__, {:run, :stale, args}, :infinity)
  end

  def unlock do
    GenServer.cast(__MODULE__, :unlock)
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)

    ExUnit.start(
      autorun: false,
      formatters: [
        ExUnit.CLIFormatter,
        Bonfire.Common.Test.Interactive.Observer
      ],
      exclude: Bonfire.Common.RuntimeConfig.skip_test_tags()
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:watch_tests, only}, state) do
    {:ok, pid} =
      Task.start(fn ->
        cmd = "fswatch lib test forks/*/test forks/*/lib"
        port = Port.open({:spawn, cmd}, [:binary, :exit_status])
        watch_loop(port, only)
      end)

    {:noreply, %{state | watcher: pid}}
  end

  @impl true
  def handle_cast(:unwatch_tests, %{watcher: pid} = state) do
    if is_nil(pid) or not Process.alive?(pid) do
      IO.puts("Watcher not running!")
    else
      Process.exit(pid, :kill)
    end

    {:noreply, %{state | watcher: nil}}
  end

  @impl true
  def handle_cast({:run, mode, only}, %{lock: false} = state) do
    do_run_tests(mode, only)
    {:noreply, %{state | lock: true}}
  end

  @impl true
  def handle_cast({:run, _mode, _}, %{lock: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:unlock, state) do
    {:noreply, %{state | lock: false}}
  end

  @impl true
  def handle_call({:run, _mode, _}, _from, %{lock: true} = state) do
    {:reply, :locked, state}
  end

  @impl true
  def handle_call({:run, mode, args}, _from, %{lock: false} = state) do
    do_run_tests(mode, args)
    {:reply, :ok, %{state | lock: true}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp watch_loop(port, only) do
    receive do
      {^port, {:data, _msg}} ->
        GenServer.cast(__MODULE__, {:run, :stale, only})
        watch_loop(port, only)
    end
  end

  defp do_run_tests(mode, only) do
    IEx.Helpers.recompile()

    # Reset config
    ExUnit.configure(
      exclude: [],
      include: [],
      only_test_ids: nil
    )

    Code.required_files()
    |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
    |> Code.unrequire_files()

    args = ["--max-cases", "1"]

    args =
      case mode do
        :all ->
          args

        :failed ->
          args ++ ["--failed"]

        :stale ->
          args ++ ["--stale"]
      end

    args =
      case only do
        _ when is_binary(only) ->
          args ++ [only]

        _ ->
          args
      end

    result =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Test.run(args)
      end)

    # if result =~ ~r/No stale tests/ or
    #      result =~ ~r/There are no tests to run/ do
    Bonfire.Common.Test.Interactive.unlock()
    # end

    IO.puts(result)
  end

  def setup_test_repo(tags) do
    wrap_test_in_transaction_and_rollback = System.get_env("START_SERVER") != "true"

    :ok =
      Ecto.Adapters.SQL.Sandbox.checkout(Bonfire.Common.Repo,
        sandbox: wrap_test_in_transaction_and_rollback
      )

    if not wrap_test_in_transaction_and_rollback or !tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Bonfire.Common.Repo, {:shared, self()})
    end
  end
end
