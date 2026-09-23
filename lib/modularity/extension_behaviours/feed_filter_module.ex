# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Common.FeedFilterModule do
  @moduledoc """
  A global registry of modules that can turn a feed filter into query terms.

  A filter belongs to whatever owns the thing it filters on: a Tagged row is `bonfire_tag`'s, a media type is `bonfire_files`', a circle is `bonfire_boundaries`'. Those extensions cannot be named by the feed loader, which would mean depending on them, and several of them cannot name it either, since it already depends on them. So each declares itself here instead, and the loader asks this registry.

  Lives in `bonfire_common` (not `bonfire_social`) for that second reason: `bonfire_social` depends on `bonfire_tag`, so a registry inside the feed loader's own extension would be unreachable from the extensions that most need it. Same reasoning as `Bonfire.Common.ReindexModule`.

  A module implements `maybe_filter/3` for the keys it knows and returns the query untouched for everything else, since every registered module is offered every filter. The key itself is declared separately, as a field on `Bonfire.Social.FeedFilters` through `Exto` (`config :bonfire_social, Bonfire.Social.FeedFilters, field: [...]`), because a struct's fields have to exist when it compiles. Both halves are needed: a key with no module here validates and then filters nothing.
  """
  @behaviour Bonfire.Common.ExtensionBehaviour
  use Bonfire.Common.Utils, only: []

  @doc "Declares a feed filter module (return `__MODULE__`)"
  @callback feed_filter_module() :: module

  @doc "Applies one `{filter_key, value}` to a feed query, returning it unchanged for keys this module does not handle"
  @callback maybe_filter(query :: any, filter :: {atom, any}, opts :: keyword) :: any

  @spec modules() :: [atom]
  def modules() do
    Bonfire.Common.ExtensionBehaviour.behaviour_modules(__MODULE__)
  end
end
