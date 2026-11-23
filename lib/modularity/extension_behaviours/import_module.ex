# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ImportModule do
  @moduledoc """
  How an extension hooks into importing (see `Bonfire.Common.Import`), in one or both of two roles. Every callback is optional.

  - Source: where the data comes from, such as an account archive zip or a WordPress export. `stage/1` checks the input and lists what it offers, with counts, so the person can pick; `materialize/3` turns the picked items into jobs, which `Bonfire.Common.Import.import_staged/3` queues.
  - Op: what to do with one item, such as following an account or importing a post. `import_ops/0` declares the ops it handles and `perform_import/3` does one, in a job of the import worker.

  The two vary independently: one archive feeds ops owned by several extensions, and a single CSV upload, a live migration or a site sync feed ops with no staged file.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour

  @typedoc """
  One thing a source offers. `key` is an atom for an importable item, since it maps to an import type, and the file name for one that can't be imported. `detail` replaces the count in its label when given.

  `options` are choices about how the item is imported, shown as checkboxes under it: each ticked one reaches `materialize/3` as `key: true` in its opts, and each unticked one as `key: false`. An option with `admin_only?: true` is only offered to, and only honoured for, an instance admin.
  """
  @type item :: %{
          required(:key) => atom() | String.t(),
          required(:label) => String.t(),
          required(:count) => non_neg_integer() | nil,
          required(:importable?) => boolean(),
          required(:reason) => String.t() | nil,
          optional(:detail) => String.t(),
          optional(:options) => [option()]
        }

  @typedoc "A choice about how an item is imported (see `t:item/0`)."
  @type option :: %{
          required(:key) => atom(),
          required(:label) => String.t(),
          required(:default) => boolean(),
          optional(:admin_only?) => boolean()
        }

  @typedoc """
  What `stage/1` returns, held by the caller (eg. in a LiveView's assigns) until the import, and saved in its `dir` when the import is queued so the job preparing it can read it back. `summary` says what importing will do before it's started (eg. what's left out, what's already imported), as `%{key:, reason:}` lines.
  """
  @type staged :: %{
          required(:source) => module(),
          required(:dir) => String.t(),
          required(:items) => [item()],
          optional(:summary) => [%{key: any(), reason: String.t()}],
          optional(atom()) => any()
        }

  @typedoc """
  One batch of import jobs: one job of `op` per identifier (an op some module declares in `import_ops/0`), for the item `key` it's reported under, each job also carrying `args` (eg. the staged media dir), at Oban `priority` (lower runs first, default 1).
  """
  @type job :: %{
          required(:key) => atom(),
          required(:op) => String.t(),
          required(:identifiers) => list(),
          optional(:args) => map(),
          optional(:priority) => non_neg_integer()
        }

  @typedoc """
  The picked items of a staged import, ready to import: the `jobs` to queue, in the order to queue them; what the source did itself rather than queueing (`done`, by item key, eg. `%{profile: :ok}`); what it left out (`skipped`) and what comes in differently from the rest (`notes`), each a list of `%{key:, reason:}` for the report.
  """
  @type materialized :: %{
          required(:jobs) => [job()],
          optional(:done) => %{optional(atom()) => any()},
          optional(:skipped) => [%{key: any(), reason: String.t()}],
          optional(:notes) => [%{key: any(), reason: String.t()}]
        }

  @doc "Source role: declares this module as a source, returning its key (eg. `:wordpress`), as the import form's type dropdown sends it."
  @callback import_source() :: atom()

  @doc "Source role: what the import form's type dropdown calls this source, localised for the person, so it's called each time rather than cached."
  @callback import_source_label() :: String.t()

  @doc "Source role: checks the input and lists what it offers."
  @callback stage(input :: any()) :: {:ok, staged()} | {:error, any()}

  @doc "Source role: turns the picked items of a staged import into jobs (see `t:materialized/0`), in the job preparing the import. `opts` has `current_user:` (who's importing) and each of the picked items' options as `key: true | false` (see `t:item/0`)."
  @callback materialize(staged(), keys :: [atom()], opts :: Keyword.t()) ::
              {:ok, materialized()} | {:error, any()}

  @doc "Op role: declares the ops this module handles, eg. `[\"follows_import\"]`."
  @callback import_ops() :: [String.t()]

  @doc "Op role: what the import status page calls an op, localised for the person."
  @callback import_op_label(op :: String.t()) :: String.t() | nil

  @doc "Op role: what the import status page says one of an op's jobs is doing (eg. \"Following user\"), localised for the person. Without it, the page shows the label."
  @callback import_op_phrase(op :: String.t()) :: String.t() | nil

  @doc "Op role: imports one item. `opts` has `current_user:`, or `scope: :instance_wide` with `skip_boundary_check: true`, plus what the job carries for all its items: `media_dir:`, and every other arg the source queued it with as `args:` (a map with string keys)."
  @callback perform_import(op :: String.t(), identifier :: any(), opts :: Keyword.t()) ::
              :ok | {:ok, any()} | {:error, any()}

  @optional_callbacks import_source: 0,
                      import_source_label: 0,
                      stage: 1,
                      materialize: 3,
                      import_ops: 0,
                      import_op_label: 1,
                      import_op_phrase: 1,
                      perform_import: 3

  @doc "The modules that adopt this behaviour."
  @spec modules() :: [atom]
  def modules do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end
end
