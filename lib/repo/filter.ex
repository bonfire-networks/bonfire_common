defmodule Bonfire.Common.Repo.Filter do
  @moduledoc """
  `query_filter` brings convenience and shortens the boilterplate of ecto queries

  Common filters available include:

  - `preload` - Preloads fields onto the query results
  - `start_date` - Query for items inserted after this date
  - `end_date` - Query for items inserted before this date
  - `before` - Get items with IDs before this value
  - `after` - Get items with IDs after this value
  - `ids` - Get items with a list of ids
  - `first` - Gets the first n items
  - `last` - Gets the last n items
  - `limit` - Gets the first n items
  - `offset` - Offsets limit by n items
  - `search` - ***Warning:*** This requires schemas using this to have a `&by_search(query, val)` function

  You are also able to filter on any natural field of a model, as well as use

  - gte/gt
  - lte/lt
  - like/ilike
  - is_nil/not(is_nil)

  ```elixir
  query_filter(User, %{name: %{ilike: "steve"}})
  query_filter(User, %{name: %{ilike: "steve"}}, :last_name, :asc)
  query_filter(User, %{name: %{age: %{gte: 18, lte: 30}}})
  query_filter(User, %{name: %{is_banned: %{!=: nil}}})
  query_filter(User, %{name: %{is_banned: %{==: nil}}})

  my_query = query_filter(User, %{name: "Billy"})
  query_filter(my_query, %{last_name: "Joe"})
  ```
  """

  def query_filter(
        module_or_query,
        filters,
        order_by_prop \\ :id,
        order_direction \\ :desc
      ) do
    # EctoSparkles.Filter.query_params(module_or_query, filters, order_by_prop, order_direction)
    EctoShorts.filter(module_or_query, filters, order_by_prop, order_direction)
  end
end
