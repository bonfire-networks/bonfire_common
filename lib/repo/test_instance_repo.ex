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
    declare_primary_instance()
  end

  def get_parent_instance_meta do
    %{
      current_endpoint: ProcessTree.get(:phoenix_endpoint_module),
      ecto_repo_module: ProcessTree.get(:ecto_repo_module),
      oban_testing: ProcessTree.get(:oban_testing),
      tesla_mock: ProcessTree.get(Tesla.Mock),
      pid: self()
    }
  end

  def set_child_instance(parent_pid \\ nil, instance_meta)

  def set_child_instance(parent_pid, repo) when is_binary(repo) do
    set_child_instance(parent_pid, %{ecto_repo_module: String.to_existing_atom(repo)})
  end

  def set_child_instance(parent_pid, repo) when is_atom(repo) and not is_nil(repo) do
    set_child_instance(parent_pid, %{ecto_repo_module: repo})
  end

  def set_child_instance(parent_pid, %{} = instance_meta) do
    if pid = parent_pid || instance_meta[:pid], do: Process.put(:task_parent_pid, pid)

    if oban_testing = instance_meta[:oban_testing], do: Process.put(:oban_testing, oban_testing)
    # , else: Process.delete(:oban_testing)

    if is_function(instance_meta[:tesla_mock]),
      do: Process.put(Tesla.Mock, instance_meta[:tesla_mock])

    maybe_declare_test_instance(
      instance_meta[:current_endpoint] || instance_meta[:ecto_repo_module]
    )
  end

  def maybe_declare_test_instance(v)
      when v == true or v == Bonfire.Web.FakeRemoteEndpoint or
             v == Bonfire.Common.TestInstanceRepo do
    declare_test_instance()

    # Boruta.Config.repo() |> debug("boruta repo")
  end

  def maybe_declare_test_instance(other) do
    other |> info("declaring primary instance for")
    declare_primary_instance()
  end

  def declare_primary_instance() do
    Logger.metadata(instance: :primary)

    repo = default_repo()
    prev_configured_repo = Config.repo()

    process_put(
      phoenix_endpoint_module: default_endpoint(),
      ecto_repo_module: repo
    )

    repo.put_dynamic_repo(repo)

    if Boruta.Config.repo() != repo, do: Config.put([Boruta.Oauth, :repo], repo)

    configured_repo = Config.repo()

    if Config.env() == :test do
      if prev_configured_repo != repo,
        do: debug("switching from repo #{configured_repo} to #{repo}"),
        else: debug("repo already set to #{repo}")

      if Boruta.Config.repo() != repo, do: err(Boruta.Config.repo(), "wrong boruta repo")

      if configured_repo != repo, do: err(configured_repo, "wrong repo")
    end

    nil
  end

  defp declare_test_instance do
    Logger.metadata(instance: :test)
    repo = Bonfire.Common.TestInstanceRepo
    prev_configured_repo = Config.repo()

    process_put(
      phoenix_endpoint_module: Bonfire.Web.FakeRemoteEndpoint,
      ecto_repo_module: repo
    )

    default_repo().put_dynamic_repo(repo)

    Config.put([Boruta.Oauth, :repo], repo)

    configured_repo = Config.repo()

    if Config.env() == :test do
      if prev_configured_repo != repo,
        do: debug("switching from repo #{configured_repo} to #{repo}"),
        else: debug("repo already set to #{repo}")

      if Boruta.Config.repo() != repo, do: err(Boruta.Config.repo(), "wrong boruta repo")
    end
  end

  @doc """
  Inserts an Oban job into the correct Oban instance based on the current repo context.
  Routes to `Oban.TestInstance` when in the test instance context, otherwise to `Oban`.
  """
  def oban_insert(changeset) do
    Oban.insert(oban_name(), changeset)
  end

  @doc """
  Returns the Oban instance name for the current repo context.
  """
  def oban_name do
    case ProcessTree.get(:ecto_repo_module) do
      __MODULE__ ->
        if Process.whereis(Oban.TestInstance), do: Oban.TestInstance, else: Oban

      _ ->
        Oban
    end
  end

  # todo: put somewhere reusable
  def process_put(enum) when is_list(enum) or is_map(enum) do
    Enum.map(enum, fn {k, v} -> Process.put(k, v) end)
  end
end
