defmodule Bonfire.Common do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  @doc """
  Provides a fallback value or function when the first argument is `nil`.

  - If the first argument is not `nil`, returns the first argument as is.
  - If both arguments are `nil`, returns `nil`.
  - If the first argument is `nil` and the second argument is a function, calls the function and returns its result.
  - If the first argument is `nil` and the second argument is not a function, returns the second argument as is.

  ## Examples

      iex> maybe_fallback("value", "fallback value")
      "value"
      
      iex> maybe_fallback(nil, nil)
      nil

      iex> maybe_fallback(nil, fn -> 1+2 end)
      3

      iex> maybe_fallback(nil, "fallback value")
      "fallback value"

  """
  def maybe_fallback(nil, nil), do: nil
  def maybe_fallback(nil, fun) when is_function(fun), do: fun.()
  def maybe_fallback(nil, fallback), do: fallback
  def maybe_fallback(%Ecto.Association.NotLoaded{}, fun) when is_function(fun), do: fun.()
  def maybe_fallback(%Ecto.Association.NotLoaded{}, fallback), do: fallback
  def maybe_fallback(val, _), do: val
end
