import Config

config :needle, :search_path, [:bonfire_me]

import_config "bonfire_common.exs"

config_file = if Mix.env() == :test, do: "config/test.exs", else: "config/config.exs"

cond do
  File.exists?("../bonfire/#{config_file}") ->
    IO.puts("Load #{config_file} from local clone of bonfire_spark")
    import_config "../../bonfire/#{config_file}"

  File.exists?("deps/bonfire/#{config_file}") ->
    IO.puts("Load #{config_file} from bonfire_spark dep")
    import_config "../deps/bonfire/#{config_file}"

  true ->
    IO.puts("No #{config_file} found")
    nil
end
