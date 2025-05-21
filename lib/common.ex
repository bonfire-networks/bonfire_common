defmodule Bonfire.Common do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  import Untangle

  @doc """
  Provides a fallback value or function when the first argument is `nil`.

  - If the first argument is not `nil`, returns the first argument as is.
  - If both arguments are `nil`, returns `nil`.
  - If the first argument is `nil` and the second argument is a function, calls the function and returns its result.
  - If the first argument is `nil` and the second argument is not a function, returns the second argument as is.

  ## Examples

      iex> import Bonfire.Common
      iex> maybe_fallback("value", "fallback value")
      "value"
      
      iex> import Bonfire.Common
      iex> maybe_fallback("", "fallback value")
      "fallback value"

      iex> import Bonfire.Common
      iex> maybe_fallback(nil, nil)
      nil

      iex> import Bonfire.Common
      iex> maybe_fallback(nil, fn -> 1+2 end)
      3

      iex> import Bonfire.Common
      iex> maybe_fallback(nil, "fallback value")
      "fallback value"

      iex> import Bonfire.Common
      iex> maybe_fallback(%Ecto.Association.NotLoaded{}, "fallback value")
      "fallback value"

      iex> import Bonfire.Common
      iex> Bonfire.Common.Config.put(:env, :dev)
      iex> try do
      ...>   maybe_fallback(%Ecto.Association.NotLoaded{}, :nil!)
      ...> rescue
      ...>   _ -> "exception raised"
      ...> end
      "exception raised"

  """
  def maybe_fallback(nil, nil), do: nil
  def maybe_fallback("", fallback), do: maybe_fallback(nil, fallback)

  def maybe_fallback(%Ecto.Association.NotLoaded{}, :nil!) do
    err("Required value not found")
    nil
  end

  def maybe_fallback(%Ecto.Association.NotLoaded{}, fallback), do: maybe_fallback(nil, fallback)
  def maybe_fallback(nil, fun) when is_function(fun, 0), do: fun.()
  def maybe_fallback(nil, fallback), do: fallback
  def maybe_fallback(val, _), do: val

  @doc """
  Logs or raises errors based on environment.

  This function handles errors differently depending on the environment:
  - In test: raises an exception
  - In dev: prints a warning
  - In production: logs a warning

  ## Examples

      # With just a message
      iex> # When in dev/prod (not test), does not raise and returns nil
      iex> # Only testing return value here, not side effects
      iex> Process.put(:env, :dev)
      iex> err("error message")
      # Prints: [warning] error message
      nil

      # With just data
      iex> Process.put(:env, :dev)
      iex> err(%{key: "value"})
      # Prints: [warning] An error occurred: %{key: "value"}
      nil

      # With both data and message
      iex> Process.put(:env, :dev)
      iex> err(%{key: "value"}, "Custom error message")
      # Prints: [warning] Custom error message: %{key: "value"}
      nil

  In test environment, it raises an exception:

      iex> Process.put(:env, :test)
      iex> err("test error")
      # ** (RuntimeError) test error
  """
  def err(msg) when is_binary(msg), do: err(nil, msg)
  def err(data) when not is_binary(data), do: err(data, "An error occurred")

  def err(data, msg) when is_binary(msg) do
    case Bonfire.Common.Config.env() do
      :test ->
        if data, do: IO.inspect(data)
        raise msg

      :dev ->
        # error(data, msg)
        if data,
          do: IO.warn("#{msg}: #{inspect(data)}"),
          else: IO.warn(msg)

      _prod_etc ->
        warn(data, msg)
    end
  end
end
