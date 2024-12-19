defmodule Bonfire.Common.Opts do
  @moduledoc "Helpers to handle functions' `opts` parameter (usually a `Keyword` list)"

  import Untangle
  alias Bonfire.Common
  alias Bonfire.Common.E
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Types

  @doc """
  Converts various types of input (e.g. map, user, socket, tuple) into a standardized keyword list for use as function options.

  This function handles different types of inputs and converts them to keyword lists. The conversion logic includes:

  - Extracting assigns from Phoenix socket maps, dropping specific keys.
  - Wrapping user structs into a keyword list with the key `:current_user`.
  - Wrapping other structs into a keyword list with the key `:context`.
  - Converting tuples, maps, and lists into keyword lists or wrapping them as context.

  ## Examples

      iex> to_options(%{assigns: %{user: "user_data"}})
      [user: "user_data"]

      iex> to_options(%Bonfire.Data.Identity.User{})
      [current_user: %Bonfire.Data.Identity.User{}]

      iex> to_options(%{key: "value"})
      [key: "value"]

      iex> to_options({:key, "value"})
      [key: "value"]

      iex> to_options([{:key, "value"}])
      [{:key, "value"}]

      iex> to_options(%{other: "data"})
      [other: "data"]
      
      iex> to_options(%{"non_existing_other"=> "data"})
      [__item_discarded__: true]

  """

  def to_options(user_or_socket_or_opts) do
    case user_or_socket_or_opts do
      %{assigns: %{} = assigns} = _socket ->
        assigns
        |> Map.drop([:__changed__, :streams])
        |> Enums.maybe_to_keyword_list(false, true)

      %{__struct__: schema} when schema == Bonfire.Data.Identity.User ->
        [current_user: user_or_socket_or_opts]

      _ when is_struct(user_or_socket_or_opts) ->
        [context: user_or_socket_or_opts]

      {k, v} when is_atom(k) ->
        Keyword.new([{k, v}])

      _
      when is_map(user_or_socket_or_opts) ->
        Enums.maybe_to_keyword_list(user_or_socket_or_opts, false, true)

      _
      when is_list(user_or_socket_or_opts) ->
        if Keyword.keyword?(user_or_socket_or_opts),
          do: user_or_socket_or_opts,
          else: [context: user_or_socket_or_opts]

      _ ->
        debug(Types.typeof(user_or_socket_or_opts), "No opts found in")
        [context: user_or_socket_or_opts]
    end

    # |> debug()
  end

  @doc """
  Retrieves the value associated with a key from options (list or map), or returns a fallback if the key is not present or if the value is empty.

  This function looks for the key in the options and returns its value if present. If the key is not found or the value is empty, it returns the provided fallback value.

  ## Examples

      iex> maybe_from_opts([key: "value"], :key, "default")
      "value"

      iex> maybe_from_opts([key: nil], :key, "default")
      "default"

      iex> maybe_from_opts(%{key: "value"}, :key, "default")
      "value"

      iex> maybe_from_opts(%{missing_key: "value"}, :key, "default")
      "default"

      iex> maybe_from_opts([context: %{key: "value"}], :key, "default")
      "value"

      iex> maybe_from_opts([context: %{key: "value"}], :key, "default")
      "value"

      iex> maybe_from_opts(%{context: %{key: "value"}}, :key, "default")
      "value"

      iex> maybe_from_opts(%{context: %{key: "value"}}, :key, "default")
      "value"

  """

  def maybe_from_opts(opts, key, fallback \\ nil)

  def maybe_from_opts(opts, key, fallback)
      when is_list(opts) or is_map(opts),
      do:
        maybe_do_from_opts(opts, key)
        |> Common.maybe_fallback(fn -> force_from_opts(opts, key, fallback) end)

  def maybe_from_opts(opts, key, fallback), do: force_from_opts(opts, key, fallback)

  defp maybe_do_from_opts(opts, key)
       when is_list(opts) or is_map(opts),
       do:
         E.ed(opts, key, nil)
         |> Common.maybe_fallback(fn -> E.ed(opts, :context, key, nil) end)

  defp force_from_opts(opts, key, fallback),
    do:
      to_options(opts)
      |> maybe_do_from_opts(key)
      |> Common.maybe_fallback(fallback)
end
