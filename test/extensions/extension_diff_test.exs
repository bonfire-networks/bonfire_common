defmodule Bonfire.Common.Extensions.DiffTest do
  use ExUnit.Case, async: true

  alias Bonfire.Common.Extensions.Diff

  @moduletag :backend

  # `Diff.git!/4` joins the repo path onto the app root, so the repo must live under it
  setup do
    repo_path = "_build/test/extension_diff_test_#{System.unique_integer([:positive])}"
    abs = Path.join(Diff.root(), repo_path)
    File.mkdir_p!(abs)
    on_exit(fn -> File.rm_rf!(abs) end)

    git = fn args -> {_, 0} = System.cmd("git", ["-C", abs | args], stderr_to_stdout: true) end
    git.(["init", "--quiet"])
    git.(["config", "user.email", "test@example.local"])
    git.(["config", "user.name", "Test"])
    File.write!(Path.join(abs, "a.txt"), "one\n")
    git.(["add", "."])
    git.(["commit", "--quiet", "-m", "first"])

    File.write!(Path.join(abs, "a.txt"), "two\n")
    File.write!(Path.join(abs, "new.txt"), "new\n")

    {:ok, repo_path: repo_path, abs: abs}
  end

  test "a local extension's diff (no ref, as linked for path deps) shows its uncommitted changes, including new files",
       %{repo_path: repo_path} do
    assert {:ok, _msg, patches} = Diff.generate_diff(nil, repo_path)
    assert patches |> Enum.map(& &1.to) |> Enum.sort() == ["a.txt", "new.txt"]
  end

  test "a repo without local changes has no diff (so the page shows the code instead)", %{
    repo_path: repo_path,
    abs: abs
  } do
    {_, 0} = System.cmd("git", ["-C", abs, "stash", "--include-untracked", "--quiet"])

    assert {:error, :no_diff} = Diff.generate_diff(nil, repo_path)
  end

  test "a path that isn't a git repo returns git's error instead of raising" do
    # outside any repo (under the app root, git would find the app's own repo), but relative since `Diff.git!/5` joins onto the root
    abs =
      Path.join(
        System.tmp_dir!(),
        "extension_diff_not_a_repo_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(abs)
    on_exit(fn -> File.rm_rf!(abs) end)

    path =
      String.duplicate("../", length(Path.split(Diff.root())) - 1) <>
        String.trim_leading(abs, "/")

    assert {:error, msg} = Diff.generate_diff(nil, path)
    assert msg =~ "not a git repository"
  end

  test "a failing git command raises with git's own message", %{repo_path: repo_path} do
    assert_raise RuntimeError, ~r/failed with reason: "fatal: Needed a single revision/, fn ->
      Diff.git!(["rev-parse", "--verify", "no-such-ref"], repo_path)
    end
  end

  test "diffing leaves the repo's own index and config untouched", %{
    repo_path: repo_path,
    abs: abs
  } do
    config_before = File.read!(Path.join(abs, ".git/config"))

    assert {:ok, _, _} = Diff.generate_diff(nil, repo_path)

    {staged, 0} = System.cmd("git", ["-C", abs, "diff", "--cached", "--name-only"])
    assert staged == ""
    {untracked, 0} = System.cmd("git", ["-C", abs, "ls-files", "--others", "--exclude-standard"])
    assert untracked == "new.txt\n"
    assert File.read!(Path.join(abs, ".git/config")) == config_before
  end
end
