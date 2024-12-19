defmodule Bonfire.Common.EnvConfig do
  @moduledoc """
  A Want type that reads environment variables and returns them as keyword lists or map(s).

  ## Features

    - Collects environment variables with a specified prefix.
    - Allows key transformation via `:transform_keys`.
    - Supports type casting via `:want_values` using the `Want` library.
    - Supports both single (e.g. `MYAPP_DB_HOST`) and a list of configuration groups (e.g. `MYAPP_DB_1_HOST`, `MYAPP_DB_2_HOST`, etc).
    - Returns keyword lists if all keys are atoms, otherwise returns maps.

  """
  use Want.Type

  @doc """
  Casts environment variables into keyword list(s) or map(s).

  ## Options

    - `prefix` (required): Prefix for environment variable matching.
    - `transform_keys` (optional): Function to transform keys (e.g., `&String.to_existing_atom/1`).
    - `want_values` (optional): Map of key type casts with optional defaults.
    - `want_unknown_keys` (optional): Whether to also include unknown keys when using `want_values`.
    - `indexed_list` (optional): Looks for an indexed list of env vars. Default: `false`.
    - `max_index` (optional): Maximum index for indexed configs. Default: `1000`.
    - `max_empty_streak` (optional): Stops after this many consecutive missing indices. Default: `10`.

  ## Examples

  ### Basic usage (usage as a `Want` custom type)

      iex> System.put_env("TESTA_DB_HOST", "localhost")
      iex> EnvConfig.cast(System.get_env(), prefix: "TESTA_DB") 
      {:ok, %{"host"=> "localhost"}}
      # iex> Want.cast(System.get_env(), EnvConfig, prefix: "TESTA_DB") # FIXME: Want doesn't currently have a way to cast with a custom type at the top-level, only for data within a map or keyword list
      # {:ok, %{"host"=> "localhost"}}

  ### Basic usage with prefix only (direct usage)

      iex> System.put_env("TESTA_DB_HOST", "localhost")
      iex> EnvConfig.parse(System.get_env(), prefix: "TESTA_DB") 
      %{"host"=> "localhost"}

  ### Basic usage with prefix only (direct usage, uses env from `System.get_env()` by default)

      iex> System.put_env("TESTA_DB_HOST", "localhost")
      iex> EnvConfig.parse(prefix: "TESTA_DB") 
      %{"host"=> "localhost"}

  ### With key transformation

      iex> System.put_env("TESTB_DB_HOST", "localhost")
      iex> System.put_env("TESTB_DB_PORT", "5432")
      iex> EnvConfig.parse(
      ...>   prefix: "TESTB_DB",
      ...>   transform_keys: &String.to_existing_atom/1,
      ...> ) 
      ...> |> Map.new() # just to make the test assertion easier
      %{host: "localhost", port: "5432"}

  ### With type casting for specific keys

      iex> System.put_env("TESTC_DB_PORT", "5432")
      iex> System.put_env("TESTC_DB_MAX_CONNECTIONS", "100")
      iex> System.put_env("TESTC_DB_SSL", "true")
      iex> EnvConfig.parse(
      ...>   prefix: "TESTC_DB",
      ...>   want_values: %{
      ...>     port: :integer,
      ...>     max_connections: {:integer, default: 3},
      ...>     ssl: :boolean
      ...>   }
      ...> ) 
      ...> |> Map.new() # just to make the test assertion easier
      %{ssl: true, max_connections: 100, port: 5432}

  ### With type casting for only some keys, including unknown keys as well (returns a map with mixed keys)

      iex> System.put_env("TESTU_DB_PORT", "5432")
      iex> System.put_env("TESTU_DB_MAX_CONNECTIONS", "100")
      iex> %{"max_connections"=> "100", port: 5432} = EnvConfig.parse(
      ...>   prefix: "TESTU_DB",
      ...>   want_unknown_keys: true,
      ...>   want_values: %{
      ...>     port: :integer
      ...>   }
      ...> ) 

  ### With both transformation and type casting

      iex> System.put_env("TESTD_DB_HOST_", "localhost")
      iex> EnvConfig.parse(
      ...>   prefix: "TESTD_DB",
      ...>   transform_keys: &String.trim(&1, "_"),
      ...>   want_values: %{
      ...>     host: :string
      ...>   }
      ...> )
      [host: "localhost"]

  ### Indexed list of configs

      iex> System.put_env("TESTE_DB_0_HOST", "localhost")
      iex> System.put_env("TESTE_DB_1_HOST", "remote")
      iex> EnvConfig.parse(
      ...>   prefix: "TESTE_DB",
      ...>   want_values: %{
      ...>     host: :string
      ...>   },
      ...>   indexed_list: true
      ...> )
      [[host: "localhost"], [host: "remote"]]
  """
  @impl true
  def cast(input, opts) do
    case parse(input, opts) do
      {:ok, data} -> {:ok, data}
      {:error, e} -> {:error, e}
      data -> {:ok, data}
    end
  end

  def parse(input \\ nil, opts) do
    indexed_list = Keyword.get(opts, :indexed_list, false)

    parse_configs(input || System.get_env(), indexed_list, opts)
  end

  defp parse_configs(env, false, opts) do
    prefix = Keyword.fetch!(opts, :prefix)

    with {:ok, config} <- parse_env_vars(prefix, env, opts) do
      config
    end
  end

  defp parse_configs(env, true = _indexed, opts) do
    prefix = Keyword.fetch!(opts, :prefix)
    max_index = Keyword.get(opts, :max_index, 1000)
    max_empty_streak = Keyword.get(opts, :max_empty_streak, 10)

    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(max_index + 1)
    |> Stream.transform({[], 0}, fn index, {acc, empty_count} ->
      config = parse_env_vars(index, prefix, env, opts)

      case config do
        nil ->
          if empty_count >= max_empty_streak - 1 do
            {:halt, {acc, empty_count + 1}}
          else
            {[], {acc, empty_count + 1}}
          end

        {:error, e} ->
          raise RuntimeError, reason: e

        {:ok, config} ->
          {[config], {acc ++ [config], 0}}
      end
    end)
    |> Enum.to_list()
  end

  defp parse_env_vars(index \\ nil, prefix, env, opts) do
    want_unknown_keys = Keyword.get(opts, :want_unknown_keys, false)
    want_values = Keyword.get(opts, :want_values)
    transform_keys = Keyword.get(opts, :transform_keys, & &1)

    # Build the pattern based on whether we're reading an indexed list of vars
    prefix_pattern =
      if index do
        "^#{prefix}_#{index}_(.+)$"
      else
        "^#{prefix}_(.+)$"
      end

    # Get matching environment variables
    matching_vars = get_matching_vars(env, prefix_pattern)

    if matching_vars == %{} do
      nil
    else
      matching_vars
      |> Enum.map(fn {key, value} ->
        transformed_key =
          key
          |> transform_keys.()

        {transformed_key, value}
      end)
      |> maybe_want(want_unknown_keys, want_values)
    end
  end

  defp get_matching_vars(env, prefix_pattern) do
    env
    |> Enum.filter(fn {key, _value} ->
      Regex.match?(~r/#{prefix_pattern}/i, key)
    end)
    |> Enum.map(fn {key, value} ->
      [_full, key_suffix] = Regex.run(~r/#{prefix_pattern}/i, key)

      {String.downcase(key_suffix), value}
    end)
    |> Enum.into(%{})
  end

  def maybe_want(input, _, nil), do: Map.new(input)

  def maybe_want(input, true, want_values) do
    with {:ok, wanted_map} <- Want.map(input, prepare_want_map_schema(want_values)) do
      # TODO: submit PR to Want adding an option to include unknown keys instead
      {:ok, Enum.into(wanted_map, input) |> Map.new()}
    end
  end

  def maybe_want(input, _false, want_values) do
    Want.keywords(input, prepare_want_map_schema(want_values))
  end

  # TODO: submit PR to Want adding an option to include the type as an atom in schemas if no other options are needed
  defp prepare_want_map_schema(%{} = want) do
    want
    |> Enum.map(fn {k, v} ->
      {
        k,
        prepare_want_map_schema(v)
      }
    end)
    |> Enum.into(%{})
  end

  defp prepare_want_map_schema(nil), do: [key: :string]
  defp prepare_want_map_schema(type) when is_atom(type), do: [type: type]

  defp prepare_want_map_schema({type, opts}) when is_list(opts) and is_atom(type),
    do: Keyword.put(opts, :type, type)

  defp prepare_want_map_schema(v), do: v
end
