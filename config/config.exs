import Config

config :needle, :search_path, [:bonfire_common]

# Choose password hashing backend
# Note that this corresponds with our dependencies in mix.exs
hasher = if config_env() in [:dev, :test], do: Pbkdf2, else: Argon2
config :bonfire_data_identity, Bonfire.Data.Identity.Credential, hasher_module: hasher

import_config "bonfire_common.exs"

config_file = if Mix.env() == :test, do: "config/test.exs", else: "config/config.exs"

cond do
  File.exists?("../bonfire/#{config_file}") ->
    IO.puts("Load #{config_file} from local clone of `bonfire` dep")
    import_config "../../bonfire/#{config_file}"

  File.exists?("deps/bonfire/#{config_file}") ->
    IO.puts("Load #{config_file} from `bonfire` dep")
    import_config "../deps/bonfire/#{config_file}"

  true ->
    IO.puts("No #{config_file} found")
    nil
end
