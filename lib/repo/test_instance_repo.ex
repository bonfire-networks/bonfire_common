defmodule Bonfire.Common.TestInstanceRepo do
  use Bonfire.Common.RepoTemplate
  alias Bonfire.Common.Config

  # def init(:supervisor, config) do
  #    # insert fixtures on startup (because running them as part of migrations inserts in primary repo)
  #   apply(&Bonfire.Boundaries.Fixtures.insert/0)

  #   {:ok, config}
  # end
  # def init(:runtime, config), do: {:ok, config}

  def apply(fun) do
    # Config.put(bonfire: [
    #   repo_module: Bonfire.Common.TestInstanceRepo,
    #   endpoint_module: Bonfire.Web.FakeRemoteEndpoint
    # ])
    Process.put(:ecto_repo_module, Bonfire.Common.TestInstanceRepo)
    Process.put(:phoenix_endpoint_module, Bonfire.Web.FakeRemoteEndpoint)

    fun.()
  after
    # Config.put(bonfire: [
    #   repo_module: Bonfire.Common.Repo,
    #   endpoint_module: Bonfire.Web.Endpoint
    # ])
    Process.put(:ecto_repo_module, Bonfire.Common.Repo)
    Process.put(:phoenix_endpoint_module, Bonfire.Web.Endpoint)
  end
end
