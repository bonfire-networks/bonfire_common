import Config

config :bonfire_common,
  repo_module: Bonfire.Repo,
  otp_app: :bonfire,
  common_errors: %{
    unauthorized: {403, "You do not have permission to {verb} this."},
    unknown_resource: {400, "Unknown resource."},
    invalid_argument: {400, "Invalid arguments passed."},
    unauthenticated: {401, "You need to be logged in."},
    password_hash_missing: {401, "Reset your password to login."},
    incorrect_password: {401, "Invalid credentials."},
    not_found: {404, "Not found."},
    user_not_found: {404, "User not found."},
    unknown: {500, "Something went wrong."}
  }
