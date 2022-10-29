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
    Process.put(:phoenix_endpoint_module, default_endpoint())
    Process.put(:ecto_repo_module, repo)
    repo.put_dynamic_repo(repo)
    Logger.metadata(instance: :primary)
  end

  def maybe_declare_test_instance(Bonfire.Web.FakeRemoteEndpoint) do
    declare_test_instance()
  end

  def maybe_declare_test_instance(_) do
    Logger.metadata(instance: :primary)
    nil
  end

  defp declare_test_instance do
    Process.put(:phoenix_endpoint_module, Bonfire.Web.FakeRemoteEndpoint)
    Process.put(:ecto_repo_module, Bonfire.Common.TestInstanceRepo)
    default_repo().put_dynamic_repo(Bonfire.Common.TestInstanceRepo)
    Logger.metadata(instance: :test)
  end
end
