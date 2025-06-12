defmodule Bonfire.Common.ReadOnlyRepo do
  @moduledoc """
      An `Ecto.Repo` with no insert/update/delete functions defined
  """
  use Bonfire.Common.RepoTemplate,
    otp_app:
      Bonfire.Common.Config.__get__(:umbrella_otp_app) ||
        Bonfire.Common.Config.__get__(:otp_app) || :bonfire_common,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
