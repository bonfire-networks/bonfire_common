defmodule IExWatchTests do
  @moduledoc """
  This utility allows to get the same effect of using
  `fcwatch | mix test --stale --listen-on-stdin` to watch for
  code changes and run stale tests, but with more control and
  without the starting time penalty.

  Note that watching requires fswatch on your system.
  Eg on Mac run `brew install fswatch`.

  To use it, in your project's `.iex` file add:
  ```
  unless GenServer.whereis(IExWatchTests) do
    {:ok, pid} = IExWatchTests.start_link()
    # Process will not exit when the iex goes out
    Process.unlink(pid)
  end
  import IExWatchTests.Helpers
  ```
  Then to call `iex` and run tests just do:
  ```
  MIX_ENV=test iex -S mix
  ```
  The `IExWatchTests.Helpers` allows to call `f` and `s` and `a`
  to run failed, stale and all tests respectively.
  You can call `w` to watch tests and `uw` to unwatch.
  There is a really simple throttle mecanism that disallow running the suite concurrently.
  """

  use GenServer

  defmodule Helpers do
    defdelegate t, to: IExWatchTests, as: :run_all_tests
    defdelegate f, to: IExWatchTests, as: :run_failed_tests
    defdelegate s, to: IExWatchTests, as: :run_stale_tests
    defdelegate w, to: IExWatchTests, as: :watch_tests
    defdelegate uw, to: IExWatchTests, as: :unwatch_tests

    def ready, do: IO.puts "IExWatchTests is ready... Enter `w` to start watching for changes and `uw` to unwatch. Or run tests manually with `f` for previously-failed tests, `s` for stale ones, and `t` for everything."
  end

  defmodule Observer do
    use GenServer

    @impl true
    def init(opts) do
      {:ok, opts}
    end

    @impl true
    def handle_cast({:suite_finished, _times_us}, config) do
      IExWatchTests.unlock()
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

  def watch_tests do
    GenServer.cast(__MODULE__, :watch_tests)
  end

  def unwatch_tests do
    GenServer.cast(__MODULE__, :unwatch_tests)
  end

  def run_all_tests do
    GenServer.call(__MODULE__, {:run, :all}, :infinity)
  end

  def run_failed_tests do
    GenServer.call(__MODULE__, {:run, :failed}, :infinity)
  end

  def run_stale_tests do
    GenServer.call(__MODULE__, {:run, :stale}, :infinity)
  end

  def unlock do
    GenServer.cast(__MODULE__, :unlock)
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    ExUnit.start(autorun: false, formatters: [ExUnit.CLIFormatter, IExWatchTests.Observer])
    {:ok, state}
  end

  @impl true
  def handle_cast(:watch_tests, state) do
    {:ok, pid} =
      Task.start(fn ->
        cmd = "fswatch lib test forks/*/test forks/*/lib"
        port = Port.open({:spawn, cmd}, [:binary, :exit_status])
        watch_loop(port)
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
  def handle_cast({:run, mode}, %{lock: false} = state) do
    do_run_tests(mode)
    {:noreply, %{state | lock: true}}
  end

  @impl true
  def handle_cast({:run, _mode}, %{lock: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:unlock, state) do
    {:noreply, %{state | lock: false}}
  end

  @impl true
  def handle_call({:run, _mode}, _from, %{lock: true} = state) do
    {:reply, :locked, state}
  end

  @impl true
  def handle_call({:run, mode}, _from, %{lock: false} = state) do
    do_run_tests(mode)
    {:reply, :ok, %{state | lock: true}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp watch_loop(port) do
    receive do
      {^port, {:data, _msg}} ->
        GenServer.cast(__MODULE__, {:run, :stale})
        watch_loop(port)
    end
  end

  defp do_run_tests(mode) do
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

    args =
      case mode do
        :all ->
          []

        :failed ->
          ["--failed"]

        :stale ->
          ["--stale"]
      end

    result =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Test.run(args)
      end)

    # if result =~ ~r/No stale tests/ or
    #      result =~ ~r/There are no tests to run/ do
      IExWatchTests.unlock()
    # end

    IO.puts(result)
  end
end
