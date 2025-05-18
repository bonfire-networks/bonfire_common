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
      
      iex> maybe_fallback("", "fallback value")
      "fallback value"

      iex> maybe_fallback(nil, nil)
      nil

      iex> maybe_fallback(nil, fn -> 1+2 end)
      3

      iex> maybe_fallback(nil, "fallback value")
      "fallback value"

      iex> maybe_fallback(%Ecto.Association.NotLoaded{}, "fallback value")
      "fallback value"

      iex> maybe_fallback(%Ecto.Association.NotLoaded{}, :nil!)
      ** (RuntimeError) Required value not found

  """
  def maybe_fallback(nil, nil), do: nil
  def maybe_fallback("", fallback), do: maybe_fallback(nil, fallback)

  def maybe_fallback(%Ecto.Association.NotLoaded{}, :nil!) do
    case Bonfire.Common.Config.env() do
      :test ->
        raise "Required value not found"

      :dev ->
        IO.warn("Required value not found")
        nil

      _ ->
        nil
    end
  end

  def maybe_fallback(%Ecto.Association.NotLoaded{}, fallback), do: maybe_fallback(nil, fallback)
  def maybe_fallback(nil, fun) when is_function(fun, 0), do: fun.()
  # def maybe_fallback(nil, :nil!) do
  #   if Bonfire.Common.Config.env() in [:test, :dev] do
  #     raise "Required value not found."
  #   else
  #     nil
  #   end
  # end
  def maybe_fallback(nil, fallback), do: fallback
  def maybe_fallback(val, _), do: val
end
