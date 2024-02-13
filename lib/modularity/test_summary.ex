defmodule Bonfire.Common.TestSummary do
  @moduledoc false
  use GenServer
  use Bonfire.Common.Utils, only: []

  @ets_table_name __MODULE__

  def init(opts) do
    IO.inspect(opts, label: "TestSummary init")
    :ets.new(@ets_table_name, [:named_table, :ordered_set, :private])
    {:ok, opts}
  end

  def handle_cast({:suite_started, _}, config) do
    IO.inspect(config, label: "Tests started, with config:")

    {:noreply, config}
  end

  def handle_cast({:module_finished, %{tests: tests} = _tested_module}, config) do
    # IO.inspect(opts, label: "Tests for module done")
    Enum.each(tests, &handle_test(&1, config))
    {:noreply, config}
  end

  def handle_cast({:suite_finished, times_us}, config) do
    # select_all = :ets.fun2ms(&(&1))
    # :ets.select(@ets_table_name, select_all)
    :ets.tab2list(@ets_table_name)
    |> IO.inspect(label: "ETS")
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.map(fn {tag, tests} ->
      IO.puts("#{length(tests)} tests #{tag}")
      # IO.inspect(tests)
    end)

    IO.inspect(times_us, label: "Tests finished")

    {:noreply, config}
  end

  def handle_cast({:sigquit, _test_or_test_module}, config) do
    IO.puts("Suite interrupted")
    handle_cast({:suite_finished, nil}, config)
  end

  def handle_cast(_event, config) do
    # IO.inspect(opts, label: "Other test event")
    {:noreply, config}
  end

  def handle_test(%{state: nil} = test, _config),
    do: post_test(test, :ok, "passed OK")

  def handle_test(%{state: {:invalid, module}} = test, _config),
    do: post_test(test, "The test seems invalid (#{inspect(module)})", "invalid")

  # NOTE: skipped/excluded tests are not included in :module_finished
  def handle_test(%{state: {:skipped, reason}} = test, _config),
    do: post_test(test, "The test was skipped (#{reason})", "skipped")

  def handle_test(%{state: {:excluded, reason}} = test, _config),
    do: post_test(test, "The test was excluded (#{reason})", "excluded")

  def handle_test(%{state: {:failed, failures}} = test, config) do
    error =
      ExUnit.Formatter.format_test_failure(
        test,
        failures,
        1,
        90000,
        &formatter(&1, &2, config)
      )
      |> String.split(["\n"])
      |> Enum.drop(2)
      |> Enum.join("\n")

    post_test(test, error, "failed")
  end

  def post_test(test, status_or_comment, tag) do
    # IO.inspect(test)
    IO.puts(
      "\n#{test.name} :: #{status_or_comment}\n#{test.tags.file}:#{test.tags.line} @ #{test.module}}\n"
    )

    :ets.insert_new(@ets_table_name, {test.name, tag})
  end

  defp formatter(:blame_diff, msg, %{colors: _colors} = _config) do
    "-" <> msg <> "-"
  end

  # defp formatter(:extra_info, _msg, _config), do: ""

  defp formatter(_, msg, _config), do: msg
end
