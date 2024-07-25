defmodule Bonfire.Common.TextExtended do
  import Bonfire.Common.Extend
  extend_module(Bonfire.Common.Text)

  def blank?(str_or_nil \\ 1) do
    require Logger
    Logger.info("Check if #{str_or_nil} is considered blank")
    # call function from original module:
    super(str_or_nil)
  end

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      1

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """

  def blank?(str_or_nil), do: "" == str_or_nil |> to_string() |> String.trim()

  @doc """
  Returns the length of the input based on its type.

  ## Examples

      iex> strlen("hello")
      5

      iex> strlen([1, 2, 3])
      3

      iex> strlen(%{})
      0

      iex> strlen(nil)
      0

      iex> strlen(0)
      0

      iex> strlen(123)
      1
  """
end
