defmodule Bonfire.Common.TestInstanceRepo do
  @moduledoc """
  Special Ecto Repo used for federation testing.

  Note: more generic functions are defined in `Bonfire.Common.RepoTemplate`
  """

  use Bonfire.Common.Config
  # use Patch

  use Bonfire.Common.RepoTemplate,
    otp_app:
      Bonfire.Common.Config.__get__(:umbrella_otp_app) ||
        Bonfire.Common.Config.__get__(:otp_app) || :bonfire_common,
    adapter: Ecto.Adapters.Postgres

  require Logger

  def default_repo, do: Config.get!(:repo_module)
  def default_endpoint, do: Config.get!(:endpoint_module)

  def apply(fun) do
    declare_test_instance()
    fun.()
  after
    repo = default_repo()

    process_put(
      phoenix_endpoint_module: default_endpoint(),
      ecto_repo_module: repo
    )

    maybe_declare_test_instance(false)
  end

  def maybe_declare_test_instance(v) when v == true or v == Bonfire.Web.FakeRemoteEndpoint do
    declare_test_instance()

    Boruta.Config.repo() |> flood("boruta repo")
  end

  def maybe_declare_test_instance(_) do
    # Logger.metadata(instance: :primary)

    repo = default_repo()

    if Config.env() == :test do
      if Config.repo() != repo, do: err(Config.repo(), "wrong repo")
      if Boruta.Config.repo() != repo, do: Config.put([Boruta.Oauth, :repo], repo)
      if Boruta.Config.repo() != repo, do: err(Boruta.Config.repo(), "wrong repo")
    end

    Boruta.Config.repo() |> flood("boruta repo")

    repo.put_dynamic_repo(repo)

    nil
  end

  defp declare_test_instance do
    repo = Bonfire.Common.TestInstanceRepo

    process_put(
      phoenix_endpoint_module: Bonfire.Web.FakeRemoteEndpoint,
      ecto_repo_module: repo
    )

    # if Config.env() ==:test, do: 
    #   Patch.patch(Boruta.Config, :repo, repo)

    Config.put([Boruta.Oauth, :repo], repo)

    default_repo().put_dynamic_repo(repo)
    # Logger.metadata(instance: :test)
  end

  # todo: put somewhere reusable
  def process_put(enum) when is_list(enum) or is_map(enum) do
    Enum.map(enum, fn {k, v} -> Process.put(k, v) end)
  end
end
