defmodule Bonfire.Common.Opts do
  import Untangle
  alias Bonfire.Common
  alias Bonfire.Common.E
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Types

  @doc """
  Converts a map, user, socket, tuple, etc, to a keyword list for standardised use as function options.
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
  end

  @doc """
  Returns the value of a key from options keyword list or map, or a fallback if not present or empty.
  """
  def maybe_from_opts(opts, key, fallback \\ nil)

  def maybe_from_opts(opts, key, fallback)
      when is_list(opts) or is_map(opts),
      do:
        E.e(opts, key, nil)
        |> Common.maybe_fallback(fn -> force_from_opts(opts, key, fallback) end)

  def maybe_from_opts(opts, key, fallback), do: force_from_opts(opts, key, fallback)

  defp force_from_opts(opts, key, fallback),
    do: to_options(opts) |> E.e(key, nil) |> Common.maybe_fallback(fallback)
end
