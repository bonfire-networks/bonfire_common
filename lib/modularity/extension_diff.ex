defmodule Bonfire.Common.Extensions.Diff do
  import Untangle

  def generate_diff(repo_path) do
    case repo_latest_diff(repo_path) do
      {:ok, diff} ->
        # IO.inspect(diff)
        # render_diff(diff)
        {:ok, diff}

      other ->
        error(other)
        {:error, "Could not generate latest diff."}
    end
  catch
    :throw, {:error, :invalid_diff} ->
      {:error, "Invalid diff."}
  end

  def repo_latest_diff(repo_path) do
    path_diff = tmp_path(Regex.replace(~r/[^a-z0-9_]+/i, repo_path, "_"))

    with :ok <- git_fetch(repo_path),
         :ok <- git_pre_configure(repo_path),
         :ok <- git_add_all(repo_path),
         :ok <- git_diff(repo_path, path_diff),
         {:ok, diff} <- parse_repo_latest_diff(path_diff) do
      {:ok, diff}
    else
      error ->
        error(error, "Failed to create diff for #{repo_path} at #{path_diff}")
    end
  end

  def parse_repo_latest_diff(path_diff) do
    with diff when is_binary(diff) and diff != "" <- File.read!(path_diff) do
      # |> debug("path_diff")
      GitDiff.parse_patch(diff)
    else
      _ ->
        error("No diff patch generated")
    end
  end

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

  def git_diff(repo_path, path_output, extra_opt \\ "--cached") do
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
        "--output=#{path_output}"
      ],
      repo_path
    )
  end

  def git!(args, repo_path \\ ".", into \\ default_into()) do
    root = root()
    debug(%{repo: repo_path, git: args, cwd: root})
    # original_cwd = root

    File.cd!(repo_path, fn ->
      opts = cmd_opts(into: into, stderr_to_stdout: true)

      case System.cmd("git", args, opts) do
        {_response, 0} ->
          # debug(response, "git_response")
          :ok

        {response, _} ->
          raise(
            "Command \"git #{Enum.join(args, " ")}\" failed with reason: #{inspect(response)}"
          )
      end
    end)
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
