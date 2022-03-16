defmodule Bonfire.Common.TestSummary do
  @moduledoc false
  use GenServer
  use Bonfire.Common.Utils, only: []

  @ets_table_name __MODULE__

  def init(opts) do
    dump(opts, "TestSummary init")
    :ets.new(@ets_table_name, [:named_table, :ordered_set, :private])
    {:ok, opts}
  end

  def handle_cast({:suite_started, _opts}, config) do
    dump(config, "Tests started, with config:")

    {:noreply, config}
  end

  def handle_cast({:module_finished, %{tests: tests} = tested_module}, config) do
    # dump(tested_module, "Tests for module done")
    Enum.each(tests, &handle_test(&1, config))
    {:noreply, config}
  end

  def handle_cast({:suite_finished, times_us}, config) do
    dump(times_us, "Tests finished")

    select_all = :ets.fun2ms(&(&1))
    :ets.select(@ets_table_name, select_all)
    |> dump("ETS")
    |> Enum.each(&( IO.puts(elem(&1, 1)) ))

    {:noreply, config}
  end

  def handle_cast({:sigquit, _test_or_test_module}, config) do
    dump("Suite interrupted")
    handle_cast({:suite_finished, nil}, config)
  end

  def handle_cast(event, config) do
    # dump(event, "Other test event")
    {:noreply, config}
  end

  def handle_test(%{state: nil} = test, _config), do: post_test(test, :ok, ["Test OK"])
  def handle_test(%{state: {:invalid, module}} = test, _config), do: post_test(test, "The test seems invalid (#{inspect module})", ["Test fails"])

  # NOTE: skipped/excluded tests are not included in :module_finished
  def handle_test(%{state: {:skipped, reason}} = test, _config), do: post_test(test, "The test was skipped (#{reason})", ["Test skipped"])
  def handle_test(%{state: {:excluded, reason}} = test, _config), do: post_test(test, "The test was excluded (#{reason})", ["Test skipped"])

  def handle_test(%{state: {:failed, failures}} = test, config) do
    error = ExUnit.Formatter.format_test_failure(test, failures, 1, 90000, &formatter(&1, &2, config))
    |> String.split(["\n"])
    |> Enum.drop(2)
    |> Enum.join("\n")

    post_test(test, error, ["Test fails"])
  end

  def post_test(test, status_or_comment, tags) do
    # IO.puts("#{test.name} : #{inspect tags}")

    case status_or_comment do
      :ok ->
        # success
        nil
      _ ->
        # IO.puts(result)
        :ets.insert_new(@ets_table_name, {test.name, {tags, status_or_comment}})
    end
  end

  defp formatter(:blame_diff, msg, %{colors: colors} = config) do
    "-" <> msg <> "-"
  end

  # defp formatter(:extra_info, _msg, _config), do: ""

  defp formatter(_, msg, _config), do: msg


end
