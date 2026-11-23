defmodule Bonfire.Common.Import do
  @moduledoc """
  Importing data into Bonfire: the framework that extensions hook into with `Bonfire.Common.ImportModule`.

  A source stages a file (eg. an account archive) and lists what it offers; the picked items become jobs of this Oban worker, one per item, on the `import` queue; each job is done by the extension that declares its op. Every source's jobs share this worker, queue and args shape (`op`, `user_id`, `identifier`), so they all show in the same import status page.
  """
  use Oban.Worker,
    queue: :import,
    max_attempts: 1

  use Arrows

  alias NimbleCSV.RFC4180, as: CSV

  import Untangle
  use Bonfire.Common.E
  use Bonfire.Common.Localise
  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  alias Bonfire.Common.ImportModule

  # which import job each of a source's lists goes to
  @list_ops %{
    following: "follows_import",
    requests: "follows_import",
    ghosted: "ghosts_import",
    silenced: "silences_import",
    blocked: "blocks_import",
    bookmarks: "bookmarks_import",
    likes: "likes_import",
    boosts: "boosts_import",
    circles: "circles_import"
  }

  # the import types a single CSV upload can be, with the op its rows go to and whether the file has a header row
  @csv_types %{
    following: {"follows_import", true},
    ghosts: {"ghosts_import", true},
    silences: {"silences_import", true},
    blocks: {"blocks_import", true},
    bookmarks: {"bookmarks_import", false},
    circles: {"circles_import", false},
    likes: {"likes_import", false},
    boosts: {"boosts_import", false}
  }

  @doc """
  Import follows, ghosts, silences, blocks, bookmarks, circles, likes or boosts from a CSV file.

  ## Examples

      iex> import_from_csv_file(:following, scope, "path/to/file.csv")

  """
  def import_from_csv_file(type, scope, path) do
    case @csv_types[type] do
      {op, with_header} -> process_csv(op, scope, read_file(path), with_header)
      nil -> error(l("Please select a valid type of import"))
    end
  end

  # TODO: import keyword filters from a Mastodon-style `custom_filters.json` export: each filter's keywords go into the person's keyword lists, `"action": "hide"` into `[:activity_pub, :mrf_keyword, :reject]` and `"warn"` into `[:activity_pub, :mrf_keyword, :warn]`, a keyword with `"whole_word": false` as `*keyword*`. Titles, contexts, expiry and per-post filters are ignored. Parsed and saved in one write, not queued per row

  @doc "Checks an uploaded account archive zip and lists what it holds (see `staged_items/1`), without importing anything yet."
  def stage_archive(zip_path), do: stage_archive(:archive, zip_path)

  @doc "Stages `path` with the source registered as `type` (a key of `archive_sources/0`, as an atom or as the string a form sends)."
  def stage_archive(type, path) do
    case archive_source(type) do
      nil -> {:error, l("This kind of import isn't available")}
      source -> source.stage(path)
    end
  end

  @doc """
  The sources a whole file can be staged from, as `[key: module]`: every enabled module adopting `Bonfire.Common.ImportModule` that declares a key in `import_source/0` (eg. `:wordpress`), so an extension adds a source just by adopting the behaviour.
  """
  def archive_sources do
    declared =
      Bonfire.Common.ExtensionBehaviour.apply_modules_cached(
        ImportModule.modules(),
        :import_source
      )

    # the cached map holds both directions (module → key and key → module), so it's read from the modules' side
    for module <- ImportModule.modules(),
        key = declared[module],
        is_atom(key) and not is_nil(key),
        Bonfire.Common.Extend.module_enabled?(module),
        do: {key, module}
  end

  @doc "The registered source for `type`, matched by name so a string from a form never becomes an atom. Nil when there's none."
  def archive_source(type) when is_atom(type) and not is_nil(type),
    do: Keyword.get(archive_sources(), type)

  def archive_source(type) when is_binary(type),
    do:
      Enum.find_value(archive_sources(), fn {key, source} -> to_string(key) == type && source end)

  def archive_source(_), do: nil

  @doc "The enabled module that does `op`, among those declaring it in their `import_ops/0`. Nil when there's none."
  def op_handler(op) when is_binary(op) do
    with module when is_atom(module) and not is_nil(module) <-
           Bonfire.Common.ExtensionBehaviour.apply_modules_cached(
             ImportModule.modules(),
             :import_ops
           )[op],
         true <- Bonfire.Common.Extend.module_enabled?(module) do
      module
    else
      _ -> nil
    end
  end

  def op_handler(_), do: nil

  # the op of the job preparing an import (see `queue_import/4`), which this module does itself
  @materialize_op "import_materialize"

  @doc "What the import status page calls `op`: its handler's label, or nil."
  def op_label(@materialize_op), do: l("Preparing import")
  def op_label(op), do: from_handler(op, :import_op_label)

  @doc "What the import status page says one of `op`'s jobs is doing: its handler's phrase, else its label, else nil. Picked by op, never by matching a label, since labels are translated."
  def op_phrase(@materialize_op), do: op_label(@materialize_op)
  def op_phrase(op), do: from_handler(op, :import_op_phrase) || op_label(op)

  defp from_handler(op, fun) do
    with handler when not is_nil(handler) <- op_handler(op),
         true <- function_exported?(handler, fun, 1) do
      apply(handler, fun, [op])
    else
      _ -> nil
    end
  end

  @doc "The import job op for a list a source holds, by the list's key (eg. `:following`, `:ghosted`, `:likes`), or nil."
  def list_op(key), do: @list_ops[key]

  @doc "What a staged import offers, each with `key`, `label`, `count`, `importable?` and the `reason` when it isn't."
  def staged_items(%{items: items}), do: items

  @doc "What importing a staged import will do, said before it's started (eg. what's left out, what's already imported), as `%{key:, reason:}` lines."
  def staged_summary(staged), do: List.wrap(staged[:summary])

  @doc "The options `item` offers `user` (see `Bonfire.Common.ImportModule.t:item/0`): an option only for instance admins is left out for anyone else."
  def offered_options(item, user) do
    for option <- List.wrap(item[:options]),
        !option[:admin_only?] or instance_admin?(user),
        do: option
  end

  @doc "Whether `user` is an instance admin: allowed to configure the instance, as its settings pages check."
  def instance_admin?(nil), do: false

  def instance_admin?(user),
    do:
      Utils.maybe_apply(Bonfire.Boundaries, :can?, [user, :configure, :instance],
        fallback_return: false
      ) == true

  # The picked items' options, as `key: true | false`: ticked or not among the options offered to `user`, matched as strings so a form's values never become atoms. An option `user` isn't offered (eg. an admin's) is left out, even when sent.
  defp option_flags(items, keys, ticked, user) do
    ticked = Enum.map(List.wrap(ticked), &to_string/1)

    for %{key: key} = item <- items,
        key in keys,
        %{key: option} <- offered_options(item, user),
        do: {option, to_string(option) in ticked}
  end

  @doc """
  Starts importing the picked items of a staged import into `user`'s account, in the background: saves `staged` in its dir and queues one job that prepares the import (see `perform/1`), which then queues the items' jobs. So a slow source (many authors' users to make, a live fetch) never holds up the person who clicked.

  `keys` are the picked items' keys, and `ticked` the values of the options ticked (see `Bonfire.Common.ImportModule.t:item/0`), both as the form sent them. Returns `{:ok, job}`, or an error when nothing importable was picked.
  """
  def queue_import(user, %{dir: dir, items: items, source: source} = staged, keys, ticked \\ []) do
    keys = List.wrap(keys)
    importable = for %{importable?: true, key: key} <- items, do: key

    cond do
      keys == [] ->
        error(l("Please pick something to import"))

      keys -- importable != [] ->
        error(keys -- importable, l("This archive doesn't hold that"))

      not staged_dir?(dir) ->
        error(dir, "Not a staged import dir")

      true ->
        File.write!(staged_path(dir), :erlang.term_to_binary(staged))

        job_enqueue([queue: :import, priority: 0], %{
          "op" => @materialize_op,
          "user_id" => Enums.id(user),
          "identifier" => to_string(source_key(source)),
          "dir" => dir,
          "keys" => Enum.map(keys, &to_string/1),
          "options" => Enum.map(List.wrap(ticked), &to_string/1)
        })
    end
  end

  defp staged_path(dir), do: Path.join(dir, "staged.term")

  defp source_key(source) do
    if function_exported?(source, :import_source, 0), do: source.import_source()
  end

  @doc "The dir on our server holding a staged import's files."
  def staged_dir(%{dir: dir}), do: dir

  @doc "Makes a new, empty dir for a source to stage an import in, under the configured `archive_dir`. The caller queues its cleanup with `enqueue_archive_cleanup/1` once staging succeeds."
  def make_staging_dir do
    dir =
      Path.join(
        Config.get([__MODULE__, :archive_dir], System.tmp_dir!()),
        "import-" <> Needle.UID.generate()
      )

    with :ok <- File.mkdir_p(dir), do: {:ok, dir}
  end

  @doc """
  Imports the picked items of a staged import into `scope` (a user): the source materializes them as jobs (see `Bonfire.Common.ImportModule.materialize/3`), which are queued here.

  `only:` takes keys from `staged_items/1`, and anything not offered there as importable is refused. The staged dir comes from `staged` as the server kept it, never from the form. Other `opts` (the items' options, eg. `include_boosts:`) are passed on to the source. A person's import goes through `queue_import/4`, which runs this in a job.

  Returns, for each item key, how many of its jobs were queued and how many failed to (`%{ok: n, error: n}`), what the source did itself (eg. `profile:`), what's left out (`skipped:`, the items that can't be imported then what the source left out) and anything that came in differently (`notes:`).
  """
  def import_staged(scope, %{source: source, items: items} = staged, opts) do
    keys = List.wrap(opts[:only])
    importable = for %{importable?: true, key: key} <- items, do: key

    case keys -- importable do
      [] when keys != [] ->
        with {:ok, materialized} <-
               source.materialize(
                 staged,
                 keys,
                 opts |> Keyword.delete(:only) |> Keyword.put(:current_user, scope)
               ) do
          user_id = Enums.id(scope)

          # in the order the source gives them
          queued =
            Enum.reduce(List.wrap(materialized[:jobs]), %{}, fn job, acc ->
              counts =
                enqueue_many(job.op, user_id, job.identifiers, job[:args] || %{},
                  priority: job[:priority]
                )

              Map.update(acc, job.key, counts, &Map.merge(&1, counts, fn _, a, b -> a + b end))
            end)

          skipped =
            for(%{importable?: false} = item <- items, do: Map.take(item, [:key, :reason])) ++
              List.wrap(materialized[:skipped])

          {:ok,
           queued
           |> Map.merge(materialized[:done] || %{})
           |> Map.put(:skipped, skipped)
           # eg. posts brought in visible only to the person
           |> Map.put(:notes, List.wrap(materialized[:notes]))}
        end

      [] ->
        error(l("Please pick something to import"))

      not_offered ->
        error(not_offered, l("This archive doesn't hold that"))
    end
  end

  @doc false
  def enqueue_archive_cleanup(dir) do
    job_enqueue(
      [
        queue: :import,
        schedule_in: div(archive_retention(), 1000)
      ],
      %{"op" => "archive_cleanup", "dir" => dir}
    )
  end

  defp read_file(path) do
    path
    |> File.read!()

    # |> File.stream!(read_ahead: 100_000) # FIXME?
  end

  defp process_csv(type, scope, csv, with_header)

  defp process_csv("circles_import" = type, scope, csv, with_header) when is_binary(csv) do
    csv
    |> parse_pairs(with_header)
    |> enqueue_many(type, scope, ...)
  end

  defp process_csv(type, scope, csv, with_header) when is_binary(csv) do
    csv
    |> parse_list(with_header)
    |> enqueue_many(type, scope, ...)
  end

  defp process_csv("circles_import" = type, scope, csv, with_header) do
    # using Stream for circles with two columns
    csv
    |> CSV.parse_stream(skip_headers: with_header)
    |> Stream.map(fn data_cols ->
      case data_cols do
        [circle_name, username] ->
          enqueue_many(
            type,
            scope,
            {String.trim(circle_name), String.trim(username) |> String.trim_leading("@")}
          )

        _ ->
          # Skip invalid rows
          {:ok, %{errors: ["Invalid format"]}}
      end
    end)
    |> results_return()
  end

  #  for any other types that have a single (relevant) column
  defp process_csv(type, scope, csv, with_header) do
    # using Stream
    csv
    |> CSV.parse_stream(skip_headers: with_header)
    |> Stream.map(fn data_cols ->
      enqueue_many(
        type,
        scope,
        data_cols
        |> List.first()
        |> String.trim()
        |> String.trim_leading("@")
      )
    end)
    |> results_return()
  end

  @doc "The identifiers in a list file (handles or URLs, one per row, in the first column), as the CSV upload and an archive's lists both hold them."
  def parse_list(csv, with_header) when is_binary(csv) do
    csv
    |> parse_rows(with_header)
    |> Enum.map(&(&1 |> List.first() |> String.trim() |> String.trim_leading("@")))
    |> Enum.reject(&(&1 == ""))
  end

  @doc "The `{circle name, handle}` pairs in a circles file."
  def parse_pairs(csv, with_header) when is_binary(csv) do
    csv
    |> parse_rows(with_header)
    # For circles, we need both columns: circle_name,username
    |> Enum.map(fn row ->
      case row do
        [circle_name, username] ->
          {String.trim(circle_name), String.trim(username) |> String.trim_leading("@")}

        [_single_value] ->
          # If only one column, skip this row as it's invalid
          nil

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == {"", ""}))
  end

  defp parse_rows(csv, with_header) do
    case csv
         |> CSV.parse_string(skip_headers: with_header) do
      # for cases where its a simple text file
      [] -> [[csv]]
      csv -> csv
    end
    |> debug()
  end

  @doc """
  Queues one job of `op` per identifier, for `scope` (a user id, or `\"instance_wide\"`), each carrying `extra_args`. Returns how many were queued and how many failed to.

  `priority:` is Oban's (a lower number runs first, default 1), eg. 0 for an outbox's posts, so someone moving here sees their own posts before their likes, bookmarks and other lists come in.

  `unique:` is Oban's too, eg. `[keys: [:op, :identifier], states: [:available, :scheduled], period: :infinity]` so a job already waiting isn't queued twice.
  """
  def enqueue_many(op, scope, identifiers, extra_args \\ %{}, opts \\ [])

  def enqueue_many(op, scope, identifiers, extra_args, opts) when is_list(identifiers) do
    identifiers
    |> Enum.map(fn identifier ->
      enqueue(op, scope, identifier, extra_args, job_spec(opts))
    end)
    |> results_return()
  end

  def enqueue_many(op, scope, identifier, extra_args, opts) do
    enqueue(op, scope, identifier, extra_args, job_spec(opts))
    |> List.wrap()
    |> results_return()
  end

  defp job_spec(opts),
    do:
      [queue: :import, priority: opts[:priority] || 1] ++
        if(opts[:unique], do: [unique: opts[:unique]], else: [])

  defp enqueue(op, scope, {circle_name, username}, _extra_args, spec),
    do:
      job_enqueue(spec, %{
        "op" => op,
        "user_id" => scope,
        "context" => circle_name,
        "identifier" => username
      })

  # `extra_args` carry what every item of one import shares, eg. the staged dir of an archive's media
  defp enqueue(op, scope, identifier, extra_args, spec),
    do:
      job_enqueue(
        spec,
        Map.merge(extra_args, %{"op" => op, "user_id" => scope, "identifier" => identifier})
      )

  defp job_enqueue(spec, worker_args),
    do: new(worker_args, spec) |> Bonfire.Common.TestInstanceRepo.oban_insert()

  defp results_return(results) do
    results
    |> Enum.frequencies_by(fn
      {:ok, %{errors: errors}} when is_list(errors) and errors != [] and not is_nil(errors) ->
        error(errors, "import error")
        :error

      {:ok, result} ->
        debug(result, "import result")
        :ok

      other ->
        error(other, "import error")
        :error
    end)
  end

  @doc """
  Performs a queued import job: its op is done by the extension declaring it (see `op_handler/1`), for the user who queued it, or instance-wide.

  ## Examples

      iex> perform(%{args: %{"op" => "follows_import", "user_id" => "user1", "identifier" => "id1"}})
      :ok

      iex> perform(%{args: %{"op" => "blocks_import", "user_id" => "instance_wide", "identifier" => "id1"}})
      :ok

  """
  def perform(%{args: %{"op" => "archive_cleanup", "dir" => dir}}) when is_binary(dir) do
    # only ever a dir staging made, so a job's args can't point the cleanup anywhere else
    if staged_dir?(dir) do
      # a job run before its time (Oban's inline mode runs scheduled jobs straight away) leaves the dir, since its import may not have read it yet
      with {:ok, %{mtime: mtime}} <- File.stat(dir, time: :posix),
           true <- System.os_time(:millisecond) - mtime * 1000 >= archive_retention() do
        File.rm_rf(dir)
      end

      :ok
    else
      error(dir, "Not a staged import dir, not deleting it")
    end
  end

  # The job preparing an import (see `queue_import/4`): reads the staged import back from its dir, matches the picked items and options against what it offers (never trusting the job's args to name anything else), and imports them for the person who queued it. Options only for instance admins are dropped for anyone else.
  def perform(%{
        args:
          %{
            "op" => @materialize_op,
            "user_id" => user_id,
            "identifier" => source_key,
            "dir" => dir
          } = args
      }) do
    with true <- staged_dir?(dir) || {:error, :not_a_staged_dir},
         {:ok, binary} <- File.read(staged_path(dir)),
         %{dir: ^dir, source: source, items: items} = staged <-
           :erlang.binary_to_term(binary, [:safe]),
         ^source <- archive_source(source_key) || {:error, :unknown_source},
         {:ok, user} <- user_by_id_or_username(user_id) do
      picked = Enum.map(List.wrap(args["keys"]), &to_string/1)
      keys = for %{importable?: true, key: key} <- items, to_string(key) in picked, do: key

      case import_staged(
             user,
             staged,
             [only: keys] ++ option_flags(items, keys, args["options"], user)
           ) do
        {:ok, _report} -> :ok
        other -> other
      end
    else
      {:error, _} = e -> e
      other -> error(other, "Could not prepare this import")
    end
  end

  def perform(%{
        args: %{"op" => op, "user_id" => "instance_wide", "identifier" => identifier}
      }) do
    # the job doesn't say who queued it, so nobody acts when it runs: a system path
    perform_op(op, identifier, scope: :instance_wide, skip_boundary_check: true)
  end

  def perform(%{
        args: %{
          "op" => "circles_import",
          "user_id" => user_id,
          "context" => circle_name,
          "identifier" => username
        }
      }) do
    with {:ok, user} <- user_by_id_or_username(user_id) do
      perform_op("circles_import", {circle_name, username}, current_user: user)
    end
  end

  def perform(%{args: %{"op" => op, "user_id" => user_id, "identifier" => identifier} = args}) do
    with {:ok, user} <- user_by_id_or_username(user_id) do
      perform_op(
        op,
        identifier,
        Enums.filter_empty(
          [
            current_user: user,
            media_dir: args["media_dir"],
            # what the source queued with every item of the import (see `enqueue_many/5`)
            args: Map.drop(args, ["op", "user_id", "identifier"])
          ],
          []
        )
      )
    end
  end

  @doc "Whether `dir` is a dir `make_staging_dir/0` made, so a job's args can't point an op at files anywhere else."
  def staged_dir?(dir) when is_binary(dir),
    do:
      Path.dirname(dir) ==
        Path.expand(Config.get([__MODULE__, :archive_dir], System.tmp_dir!())) and
        String.starts_with?(Path.basename(dir), "import-")

  def staged_dir?(_), do: false

  # an op nobody declares fails its job, so a typo or a disabled extension shows as an error rather than as done
  defp perform_op(op, identifier, opts) do
    case op_handler(op) do
      nil -> error(op, "No enabled extension handles this import")
      handler -> handler.perform_import(op, identifier, opts)
    end
  end

  defp user_by_id_or_username(user_id),
    do: Utils.maybe_apply(Bonfire.Me.Users, :by_username, [user_id])

  defp archive_retention,
    do: Config.get([__MODULE__, :archive_retention]) || to_timeout(day: 7)

  @doc "Logs an item that failed to import, and returns the error for its job."
  def handle_error(_op, identifier, error) when is_binary(identifier) do
    error(error, "could not import #{identifier}")
    {:error, Bonfire.Common.Errors.error_msg(error)}
  end

  def handle_error(_op, identifier, error) do
    error(error, "could not import #{inspect(identifier)}")
    {:error, Bonfire.Common.Errors.error_msg(error)}
  end
end
