defmodule Bonfire.Common.ObanHelpers do
  import Ecto.Query

  def list(repo, opts) when is_list(opts) do
    {conf, opts} = extract_conf(repo, opts)

    Oban.Repo.all(conf, base_query(opts))
  end

  @doc """
  List jobs for a specific user and queue
  """
  def list_jobs_queue_for_user(repo, queue, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(j in Oban.Job,
      where: j.queue == ^queue and fragment("?->>'user_id' = ?", j.args, ^user_id),
      order_by: [desc: j.id],
      limit: ^limit
    )
    |> repo.all()
  end

  @doc """
  List all jobs for a specific queue
  """
  def list_jobs_by_queue(repo, queue, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(j in Oban.Job,
      where: j.queue == ^queue,
      order_by: [desc: j.id],
      limit: ^limit
    )
    |> repo.all()
  end

  @doc """
  Get job statistics for a user and queue
  """
  def job_stats_for_user(repo, queue, user_id) do
    from(j in Oban.Job,
      where: j.queue == ^queue and fragment("?->>'user_id' = ?", j.args, ^user_id),
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Get job statistics for a queue
  """
  def job_stats_by_queue(repo, queue) do
    from(j in Oban.Job,
      where: j.queue == ^queue,
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> repo.all()
    |> Enum.into(%{})
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
end
