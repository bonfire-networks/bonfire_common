import Config

config :bonfire_common,
  otp_app: :bonfire

config :bonfire,
  default_layout_module: Bonfire.UI.Social.Web.LayoutView,
  localisation_path: "priv/localisation"
