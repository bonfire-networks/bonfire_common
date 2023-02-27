defmodule Bonfire.Common.TestInstanceRepo do
  use Bonfire.Common.RepoTemplate
  require Logger
  alias Bonfire.Common.Config

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

    repo.put_dynamic_repo(repo)
    Logger.metadata(instance: :primary)
  end

  def maybe_declare_test_instance(v) when v == true or v == Bonfire.Web.FakeRemoteEndpoint do
    declare_test_instance()
  end

  def maybe_declare_test_instance(_) do
    Logger.metadata(instance: :primary)
    nil
  end

  defp declare_test_instance do
    process_put(
      phoenix_endpoint_module: Bonfire.Web.FakeRemoteEndpoint,
      ecto_repo_module: Bonfire.Common.TestInstanceRepo
    )

    default_repo().put_dynamic_repo(Bonfire.Common.TestInstanceRepo)
    Logger.metadata(instance: :test)
  end

  # todo: put somewhere reusable
  def process_put(enum) when is_list(enum) or is_map(enum) do
    Enum.map(enum, fn {k, v} -> Process.put(k, v) end)
  end
end
