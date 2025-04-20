defmodule Bonfire.Common.Text.MarkdownBenchmark do
  @moduledoc """
  Benchmark for comparing markdown conversion performance using different libraries
  and caching strategies.

  Run with: `Bonfire.Common.Text.MarkdownBenchmark.run()`
  """

  alias Bonfire.Common.Text
  alias Faker.Lorem
  alias Faker.Markdown

  @num_samples 100
  #  3 means 30% of items will be repeated more frequently
  @repeat_percent 1
  # 0.7 means 70% chance of picking from frequent items
  @frequent_item_probability 0.8

  def run do
    run_benchmarks()
    :ok
  end

  def generate_samples do
    # Print summary of what will be generated
    IO.puts("\nGenerating markdown benchmark samples:")
    IO.puts("- Unique samples per size (short/medium/long): #{@num_samples}")
    IO.puts("- Total inputs: 6 (unique and repeated versions for each size)")
    IO.puts("-------------------------------------")

    # Helpers to generate realistic markdown for different sample types
    generate_markdown = fn length_type ->
      case length_type do
        :short ->
          Enum.join(
            [
              Markdown.emphasis()
            ],
            "\n\n"
          )

        :medium ->
          Enum.join(
            [
              Markdown.headers(),
              Markdown.markdown(),
              Markdown.unordered_list()
            ],
            "\n\n"
          )

        :long ->
          Enum.join(
            [
              Markdown.headers(),
              Markdown.markdown(),
              Markdown.unordered_list(),
              Markdown.block_code()
            ],
            "\n\n"
          )
      end
    end

    # Add a single string test
    single_str = """
    # Cache Performance Test

    This is a test with **bold** and *italic* text.

    - List item 1
    - List item 2
    - List item 3

    > Important blockquote
    """

    # Create a test with 100 identical strings
    identical_strings = List.duplicate(single_str, 100)

    # Create the base set of unique samples for each size
    unique_short = for _ <- 1..@num_samples, do: generate_markdown.(:short)
    unique_medium = for _ <- 1..@num_samples, do: generate_markdown.(:medium)
    unique_long = for _ <- 1..@num_samples, do: generate_markdown.(:long)

    # Create samples with repetition by randomly selecting from the unique sets
    # For each unique sample set, we'll create an equal-sized list but with repetition
    repeated_short = create_repeated_samples(unique_short, @num_samples)
    repeated_medium = create_repeated_samples(unique_medium, @num_samples)
    repeated_long = create_repeated_samples(unique_long, @num_samples)

    # Verification: calculate and print actual repetition rates
    short_unique_count = Enum.uniq(repeated_short) |> length()
    medium_unique_count = Enum.uniq(repeated_medium) |> length()
    long_unique_count = Enum.uniq(repeated_long) |> length()

    # Calculate detailed repetition statistics
    short_repetition_stats = calculate_repetition_stats(repeated_short)
    medium_repetition_stats = calculate_repetition_stats(repeated_medium)
    long_repetition_stats = calculate_repetition_stats(repeated_long)

    IO.puts("Generated samples with repetition:")

    IO.puts(
      "- Short repeated: #{length(repeated_short)} samples with #{short_unique_count} unique (#{short_unique_count / @num_samples * 100}% unique)"
    )

    print_repetition_details(short_repetition_stats)

    IO.puts(
      "- Medium repeated: #{length(repeated_medium)} samples with #{medium_unique_count} unique (#{medium_unique_count / @num_samples * 100}% unique)"
    )

    print_repetition_details(medium_repetition_stats)

    IO.puts(
      "- Long repeated: #{length(repeated_long)} samples with #{long_unique_count} unique (#{long_unique_count / @num_samples * 100}% unique)"
    )

    print_repetition_details(long_repetition_stats)

    %{
      # "short_unique" => unique_short,
      # "medium_unique" => unique_medium,
      # "long_unique" => unique_long,
      # "short_repeated" => repeated_short,
      # "medium_repeated" => repeated_medium,
      # "long_repeated" => repeated_long,
      "identical" => identical_strings
    }
  end

  # Helper function to create repeated samples
  defp create_repeated_samples(unique_samples, target_size) do
    unique_samples
    |> Enum.take(5)
    |> Enum.flat_map(fn str -> List.duplicate(str, 20) end)

    # # Create a subset of frequently reused content (% of original)
    # frequent_items = Enum.take_random(unique_samples, div(length(unique_samples), @repeat_percent))

    # # Use configurable percentage chance of picking from frequent items
    # Enum.map(1..target_size, fn _ ->
    #   if :rand.uniform() < @frequent_item_probability do
    #     Enum.random(frequent_items)
    #   else
    #     Enum.random(unique_samples)
    #   end
    # end)
  end

  # Helper function to calculate repetition statistics
  defp calculate_repetition_stats(samples) do
    # Count frequency of each unique item
    frequencies =
      Enum.reduce(samples, %{}, fn item, acc ->
        Map.update(acc, item, 1, &(&1 + 1))
      end)

    # Group by frequency count (how many strings appear exactly 1 time, 2 times, etc.)
    Enum.reduce(frequencies, %{}, fn {_item, count}, acc ->
      Map.update(acc, count, 1, &(&1 + 1))
    end)
  end

  # Helper function to print repetition details
  defp print_repetition_details(stats) do
    max_repeats = Map.keys(stats) |> Enum.max(fn -> 0 end)

    details =
      Enum.map_join(1..max_repeats, ", ", fn count ->
        num_strings = Map.get(stats, count, 0)

        if num_strings > 0 do
          "#{num_strings} strings appear #{count} time#{if count > 1, do: "s", else: ""}"
        else
          nil
        end
      end)
      |> String.replace(", nil", "")
      |> String.replace("nil, ", "")

    IO.puts("  Details: #{details}")
  end

  def run_benchmarks do
    inputs = generate_samples()

    Benchee.run(
      %{
        "MDEx - cold cache" => fn input ->
          Bonfire.Common.Cache.remove_all()
          Enum.each(input, &Text.maybe_markdown_to_html(&1, markdown_library: MDEx, cache: true))
        end,
        "MDEx - warm cache" => fn input ->
          Enum.each(input, &Text.maybe_markdown_to_html(&1, markdown_library: MDEx, cache: true))
        end,
        "MDEx - uncached" => fn input ->
          Enum.each(input, &Text.maybe_markdown_to_html(&1, markdown_library: MDEx, cache: false))
        end,
        "Earmark - cold cache" => fn input ->
          Bonfire.Common.Cache.remove_all()

          Enum.each(
            input,
            &Text.maybe_markdown_to_html(&1, markdown_library: Earmark, cache: true)
          )
        end,
        "Earmark - warm cache" => fn input ->
          Enum.each(
            input,
            &Text.maybe_markdown_to_html(&1, markdown_library: Earmark, cache: true)
          )
        end,
        "Earmark - uncached" => fn input ->
          Enum.each(
            input,
            &Text.maybe_markdown_to_html(&1, markdown_library: Earmark, cache: false)
          )
        end,
        "Skip markdown render" => fn input ->
          Enum.each(input, &Text.maybe_markdown_to_html(&1, markdown_library: :skip))
        end
      },
      inputs: inputs,
      # Run time in seconds
      time: 7,
      # Increased warmup time to properly warm the cache
      warmup: 20,
      memory_time: 1,
      reduction_time: 1,
      print: [
        fast_warning: false
      ],
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: "markdown_benchmark_results.html", auto_open: true}
      ]
    )
  end
end
