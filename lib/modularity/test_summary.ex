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

  def handle_cast({:test_started, %{name: name}}, config) do
    IO.puts("#{name} started...")

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
    failed_tests =
      :ets.tab2list(@ets_table_name)
      # |> IO.inspect(label: "ETS")
      |> Enum.group_by(&elem(&1, 2), &Tuple.delete_at(&1, 2))
      |> Enum.map(fn
        {"failed" = tag, tests} ->
          IO.puts("#{length(tests)} tests #{tag}:")
          for {test, location} <- tests, do: IO.puts("#{test}\n   #{location}\n")
          length(tests)

        {tag, tests} ->
          IO.puts("#{length(tests)} tests #{tag}")
          0
      end)
      |> IO.inspect(label: "test results")

    IO.inspect(times_us, label: "Tests finished")

    # Get the number of failed tests (default to 0 if none)
    failed_count =
      Enum.sum(failed_tests)
      |> IO.inspect(label: "failed_tests")

    if failed_count > 0 do
      code = min(failed_count, 255)
      IO.puts("Exiting with code #{code} due to #{failed_count} failed tests")
      System.halt(min(failed_count, 255))
    end

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
    do: post_test(test, "OK", "OK")

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
    location = "#{Path.relative_to_cwd(test.tags.file)}:#{test.tags.line} @ #{test.module}"
    IO.puts("\n#{test.name} :: #{status_or_comment}\n   #{location}\n")

    :ets.insert_new(@ets_table_name, {test.name, location, tag})
  end

  defp formatter(:blame_diff, msg, %{colors: _colors} = _config) do
    " - " <> Text.truncate(msg, 200, "...") <> " - "
  end

  # defp formatter(:extra_info, _msg, _config), do: ""

  defp formatter(_, msg, _config), do: Text.truncate(msg, 200, "...")
end
