import Config

config :bonfire_common,
  otp_app: :bonfire_common,
  env: config_env()

config :needle, :search_path, [:bonfire_common]

# Choose password hashing backend
# Note that this corresponds with our dependencies in mix.exs
hasher = if config_env() in [:dev, :test], do: Pbkdf2, else: Argon2
config :bonfire_data_identity, Bonfire.Data.Identity.Credential, hasher_module: hasher

import_config "bonfire_common.exs"

