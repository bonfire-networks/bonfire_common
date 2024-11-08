import Config

default_locale = "en"

config :bonfire_common,
  localisation_path: "priv/localisation"

config :bonfire_common,
  otp_app: :bonfire,
  ecto_repos: [Bonfire.Common.Repo]

config :bonfire, Bonfire.Common.Repo,
  database: System.get_env("POSTGRES_DB", "bonfire_dev"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  # show_sensitive_data_on_connection_error: true,
  # EctoSparkles does the logging instead
  log: false,
  stacktrace: true

## Localisation & internationalisation
# TODO: determine which keys can be set at runtime vs compile-time

config :bonfire_common, Bonfire.Common.Localise.Cldr,
  otp_app: :bonfire,
  default_locale: default_locale,
  # locales that will be made available on top of those for which gettext localisation files are available
  locales: ["fr", "en", "es"],
  providers: [
    Cldr.Language,
    Cldr.DateTime,
    Cldr.Number,
    Cldr.Unit,
    Cldr.List,
    Cldr.Calendar,
    Cldr.Territory,
    Cldr.LocaleDisplay
  ],
  gettext: Bonfire.Common.Localise.Gettext,
  # extra Gettex modules from dependencies not using the one from Bonfire.Common, so we can change their locale too
  extra_gettext: [Timex.Gettext],
  data_dir: "priv/cldr",
  add_fallback_locales: true,
  # precompile_number_formats: ["¤¤#,##0.##"],
  # precompile_transliterations: [{:latn, :arab}, {:thai, :latn}]
  force_locale_download: Mix.env() == :prod,
  generate_docs: true

config :ex_cldr_units,
  default_backend: Bonfire.Common.Localise.Cldr

config :ex_cldr,
  default_locale: default_locale,
  default_backend: Bonfire.Common.Localise.Cldr,
  json_library: Jason
