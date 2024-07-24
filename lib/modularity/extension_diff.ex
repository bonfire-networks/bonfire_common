defmodule Bonfire.Common.Extensions.Diff do
  @moduledoc """
  Provides functionality to generate and parse diffs from git repositories.
  """
  import Untangle
  use Bonfire.Common.Localise

  @doc """
  Generates a diff between the specified reference or branch and the latest commit in the repository.

  ## Parameters
    - `ref_or_branch`: The reference or branch to compare against.
    - `repo_path`: The path to the repository.

  ## Examples

      > Bonfire.Common.Extensions.Diff.generate_diff("main", "./")
      {:ok, "Diff generated successfully", "...diff content..."}

      > Bonfire.Common.Extensions.Diff.generate_diff("test_fake_branch", "./")
      {:error, "Could not generate latest diff."}
  """
  def generate_diff(ref_or_branch, repo_path) when is_binary(repo_path) do
    case repo_latest_diff(ref_or_branch, repo_path) do
      {:ok, msg, diff} ->
        # IO.inspect(diff)
        # render_diff(diff)
        {:ok, msg, diff}

      {:error, e} ->
        error(e)

      other ->
        error(other)
        {:error, "Could not generate latest diff."}
    end
  catch
    :throw, {:error, :invalid_diff} ->
      {:error, l("Invalid diff.")}
  end

  @doc """
  Fetches the latest diff from the specified reference or branch in the repository.

  ## Parameters
    - `ref_or_branch`: The reference or branch to compare against.
    - `repo_path`: The path to the repository.
    - `msg`: Optional message to include with the diff.

  ## Examples

      > Bonfire.Common.Extensions.Diff.repo_latest_diff("main", "./")
      {:ok, "Diff message", "...diff content..."}

      > Bonfire.Common.Extensions.Diff.repo_latest_diff("test_fake_branch", "./")
      {:error, :no_diff}
  """
  def repo_latest_diff(ref_or_branch, repo_path, msg \\ nil) when is_binary(repo_path) do
    path_diff = tmp_path(Regex.replace(~r/[^a-z0-9_]+/i, repo_path, "_"))

    with :ok <- git_fetch(repo_path),
         :ok <- git_pre_configure(repo_path),
         :ok <- git_add_all(repo_path),
         :ok <- git_generate_diff(ref_or_branch, repo_path, path_diff),
         {:ok, diff} <- parse_repo_latest_diff(path_diff) do
      {:ok, msg, diff}
    else
      {:error, :no_diff} ->
        {:error, :no_diff}

      # case git!(["rev-list", "--max-parents=0", "HEAD"], repo_path, "")
      #      |> debug("first commit") do
      #   ref when is_binary(ref) and ref != ref_or_branch ->
      #     repo_latest_diff(
      #       ref,
      #       repo_path,
      #       l("No changes were found. Here is the full code of the extension:")
      #     )

      #   _ ->
      #     {:error, l("No changes found.")}
      # end

      error ->
        error(error, "Failed to create diff for #{repo_path} at #{path_diff}")
    end
  end

  @doc """
  Parses the latest diff from the specified path. See `GitDiff.parse_patch/1` for details about what it outputs.

  ## Parameters
    - `path_diff`: The path to the file containing the diff.

  ## Examples

      > Bonfire.Common.Extensions.Diff.parse_repo_latest_diff("./path/to/diff.patch")
      {:ok, ...}

      > Bonfire.Common.Extensions.Diff.parse_repo_latest_diff("./path/to/empty.patch")
      {:error, :no_diff}
  """
  def parse_repo_latest_diff(path_diff) when is_binary(path_diff) do
    with diff when is_binary(diff) and diff != "" <- File.read!(path_diff) do
      # |> debug("path_diff")
      GitDiff.parse_patch(diff)
    else
      "" ->
        {:error, :no_diff}

      e ->
        error(e, "Could not find a diff patch")
    end
  end

  @doc """
  Analyzes the diff stream from the specified path.

  This function streams the diff data and processes it as it becomes available. See `GitDiff.stream_patch/1` for details on the expected output.

  ## Parameters
    - `path_diff`: The path to the file containing the diff.

  ## Examples

      > {:ok, stream} = Bonfire.Common.Extensions.Diff.analyse_repo_latest_diff_stream("./path/to/diff.patch")
  """
  def analyse_repo_latest_diff_stream(path_diff) do
    # TODO: figure out how to stream the data to LiveView as it becomes available, in which case use this function instead of `parse_repo_latest_diff`
    stream =
      File.stream!(path_diff, [:read_ahead])
      |> GitDiff.stream_patch()
      |> Stream.transform(
        fn -> :ok end,
        fn elem, :ok -> {[elem], :ok} end,
        fn :ok -> File.rm(path_diff) end
      )

    {:ok, stream}
  end

  def git_pre_configure(repo_path) do
    # Enable better diffing
    git!(["config", "core.attributesfile", "../../config/.gitattributes"], repo_path)
  end

  def git_fetch(repo_path) do
    # Fetch remote data
    # |> Kernel.++(tags_switch(opts[:tag]))
    git!(["fetch", "--force", "--quiet"], repo_path)
  end

  def git_add_all(repo_path) do
    # Add local changes for diffing purposes
    git!(["add", "."], repo_path)
  end

  @doc """
  Generates a diff and saves it to the specified output path.

  ## Parameters
    - `ref_or_branch`: The reference or branch to compare against.
    - `repo_path`: The path to the repository.
    - `path_output`: The path where the diff output will be saved.
    - `extra_opt`: Optional extra options for git diff command.

  ## Examples

      iex> Bonfire.Common.Extensions.Diff.git_generate_diff("main", "./", "./data/test_output.patch")
  """
  def git_generate_diff(ref_or_branch, repo_path, path_output, extra_opt \\ "--cached") do
    git!(
      [
        "-c",
        "core.quotepath=false",
        "-c",
        "diff.algorithm=histogram",
        "diff",
        #  "--no-index", # specify if we're diffing a repo or two paths
        # optionally diff staged changes (older git versions don't support the equivalent --staged)
        extra_opt,
        "--no-color",
        "--output=#{path_output}",
        ref_or_branch
      ],
      repo_path
    )
  end

  @doc """
  Executes a git command with the specified arguments.

  ## Parameters
    - `args`: The list of arguments for the git command.
    - `repo_path`: The path to the repository.
    - `into`: Optional destination for command output (defaults to standard output)
    - `original_cwd`: The original working directory.

  ## Examples

      iex> Bonfire.Common.Extensions.Diff.git!(["status"], "./")
  """
  def git!(args, repo_path \\ ".", into \\ default_into(), original_cwd \\ root())
      when is_list(args) do
    args = ["-C", Path.join(original_cwd, repo_path)] ++ args

    debug("Run command: git #{Enum.join(args, " ")}")

    # original_cwd 
    # |> debug("cwd")

    opts = [into: into, stderr_to_stdout: true]
    # |> cmd_opts()

    case System.cmd("git", args, opts) do
      {response, 0} ->
        info(response, "git_response")
        if into == "" and is_binary(response), do: String.trim(response), else: :ok

      {response, _} ->
        # File.cd(original_cwd)
        raise("Command \"git #{Enum.join(args, " ")}\" failed with reason: #{inspect(response)}")
    end
  rescue
    e in File.Error ->
      # File.cd(original_cwd)
      error(e, "could not read file")
      {:error, l("Could not read the code file(s).")}
  end

  defp default_into() do
    case Mix.shell() do
      Mix.Shell.IO -> IO.stream(:stdio, :line)
      _ -> ""
    end
  end

  # Attempt to set the current working directory by default.
  # This addresses an issue changing the working directory when executing from
  # within a secondary node since file I/O is done through the main node.
  defp cmd_opts(opts) do
    case root() do
      {:ok, cwd} -> Keyword.put(opts, :cd, cwd)
      _ -> opts
    end
  end

  def tmp_path(prefix) do
    random_string = Base.encode16(:crypto.strong_rand_bytes(4))
    Path.join([System.tmp_dir!(), prefix <> random_string])
  end

  def root, do: Bonfire.Common.Config.get(:root_path)
end
