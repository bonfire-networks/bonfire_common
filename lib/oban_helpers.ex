defmodule Bonfire.Common.ObanHelpers do
  import Ecto.Query
  use Untangle

  def list(repo, opts) when is_list(opts) do
    {conf, opts} = extract_conf(repo, opts)

    Oban.Repo.all(conf, base_query(opts))
  end

  @doc """
  List jobs for a user (by user_id/username) or all jobs if user_id and username are nil.
  """
  def list_jobs(repo, user_id \\ nil, username \\ nil, opts \\ []) do
    opts = if is_list(user_id) and is_nil(username) and opts == [], do: user_id, else: opts
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.get(opts, :filters, %{})

    base_query =
      Oban.Job
      |> maybe_user_filter(user_id, username)
      |> order_by([j], desc: j.id)
      |> limit(^limit)
      |> offset(^offset)

    base_query
    |> apply_job_filters(filters)
    |> debug("query for jobs")
    |> repo.all()
  end

  @doc """
  Get job statistics for a user (by user_id/username) or all jobs if user_id and username are nil.
  """
  def job_stats(repo, user_id \\ nil, username \\ nil, filters \\ %{}) do
    base_query =
      Oban.Job
      |> maybe_user_filter(user_id, username)
      |> group_by([j], j.state)
      |> select([j], {j.state, count(j.id)})

    base_query
    |> apply_job_filters(filters)
    |> repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Cancel all active jobs of a specific operation type for a user.
  """
  def cancel_jobs_by_type_for_user(repo, user_id, username, op_code) do
    from(j in Oban.Job,
      where:
        (fragment("?->>'user_id' = ?", j.args, ^user_id) or
           fragment("?->>'username' = ?", j.args, ^username)) and
          fragment("?->>'op' = ?", j.args, ^op_code) and
          j.state in ["available", "scheduled", "retryable"]
    )
    |> repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])
  end

  defp base_query(opts) do
    fields_with_opts = normalize_fields(opts)

    Oban.Job
    |> apply_where_clauses(fields_with_opts)
    |> order_by(desc: :id)
  end

  @timestamp_fields ~W(attempted_at completed_at inserted_at scheduled_at)a
  @timestamp_default_delta_seconds 1

  defp apply_where_clauses(query, []), do: query

  defp apply_where_clauses(query, [{key, value, opts} | rest]) when key in @timestamp_fields do
    delta = Keyword.get(opts, :delta, @timestamp_default_delta_seconds)

    window_start = DateTime.add(value, -delta, :second)
    window_end = DateTime.add(value, delta, :second)

    query
    |> where([j], fragment("? BETWEEN ? AND ?", field(j, ^key), ^window_start, ^window_end))
    |> apply_where_clauses(rest)
  end

  defp apply_where_clauses(query, [{key, value, _opts} | rest]) do
    query
    |> where(^[{key, value}])
    |> apply_where_clauses(rest)
  end

  defp extract_conf(repo, opts) do
    {conf_opts, opts} = Keyword.split(opts, [:prefix])

    conf =
      conf_opts
      |> Keyword.put(:repo, repo)
      |> Oban.Config.new()

    {conf, opts}
  end

  defp extract_field_opts({key, {value, field_opts}}, field_opts_acc) do
    {{key, value}, [{key, field_opts} | field_opts_acc]}
  end

  defp extract_field_opts({key, value}, field_opts_acc) do
    {{key, value}, field_opts_acc}
  end

  defp normalize_fields(opts) do
    {fields, field_opts} = Enum.map_reduce(opts, [], &extract_field_opts/2)

    args = Keyword.get(fields, :args, %{})
    keys = Keyword.keys(fields)

    args
    |> Oban.Job.new(fields)
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(keys)
    |> Enum.map(fn {key, value} -> {key, value, Keyword.get(field_opts, key, [])} end)
  end

  defp apply_job_filters(query, empty) when empty == %{}, do: query
  defp apply_job_filters(query, %{type: nil, status: nil}), do: query

  defp apply_job_filters(query, filters) do
    query
    |> apply_type_filter(Map.get(filters, :type))
    |> apply_status_filter(Map.get(filters, :status))
  end

  # Accepts a string or a list of types
  defp apply_type_filter(query, []), do: query

  defp apply_type_filter(query, types) when is_list(types) do
    where(query, [j], fragment("?->>'op' = ANY(?)", j.args, ^types))
  end

  defp apply_type_filter(query, type) when is_binary(type) do
    where(query, [j], fragment("?->>'op' = ?", j.args, ^type))
  end

  defp apply_type_filter(query, _), do: query

  defp apply_status_filter(query, nil), do: query

  defp apply_status_filter(query, "done") do
    where(query, [j], j.state in ["completed", "discarded", "cancelled"])
  end

  defp apply_status_filter(query, "successful") do
    where(query, [j], j.state == "completed")
  end

  defp apply_status_filter(query, "active") do
    where(query, [j], j.state in ["executing", "available", "scheduled", "retryable"])
  end

  defp apply_status_filter(query, "failed") do
    where(query, [j], j.state in ["discarded", "cancelled"])
  end

  defp maybe_user_filter(query, nil, nil), do: query

  defp maybe_user_filter(query, user_id, username) do
    cond do
      user_id && username ->
        where(
          query,
          [j],
          fragment("?->>'user_id' = ?", j.args, ^user_id) or
            fragment("?->>'username' = ?", j.args, ^username)
        )

      user_id ->
        where(query, [j], fragment("?->>'user_id' = ?", j.args, ^user_id))

      username ->
        where(query, [j], fragment("?->>'username' = ?", j.args, ^username))
    end
  end
end
