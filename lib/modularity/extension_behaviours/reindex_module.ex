# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.ReindexModule do
  @moduledoc """
  A global registry of modules that can (re)index a type of object into the search index
  (e.g. users, posts), used to backfill the index after enabling search or switching adapters.

  Each implementing module is *also* an `EctoSparkles.DataMigration` (defining `config`, `base_query`
  and `migrate`), so it (re)indexes its objects in throttled, keyset-paginated batches.
  `Bonfire.Search.Indexer.reindex_from_db/1` discovers every registered module via `modules/0` and runs
  them — optionally a subset (`only:`) and/or with per-module options that each module can act on (e.g.
  `users: :local | :remote | :all`) by implementing `base_query/1` (which receives those opts).

  Lives in `bonfire_common` (not `bonfire_search`) so any extension can register without a compile-time
  dependency on `bonfire_search` (which depends on them, not vice-versa).
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a reindex module (return `__MODULE__`)"
  @callback reindex_module() :: module

  @doc "Runs this module's (re)indexing with the given options (typically `Runner.run(__MODULE__, opts)`)"
  @callback reindex(opts :: keyword()) :: any

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end
end
