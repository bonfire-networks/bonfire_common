defmodule Bonfire.Common.DatesTimes do
  @moduledoc """
  Date/time helpers
  """
  use Arrows
  import Untangle

  @doc "Takes a ULID ID (or an object with one) or a `DateTime` struct, and turns the date into a relative phrase, e.g. `2 days ago`, using the `Cldr.DateTime` or `Timex` library."
  def date_from_now(date, opts \\ [])

  def date_from_now(%DateTime{} = date, opts) do
    date
    |> Bonfire.Common.Localise.Cldr.DateTime.Relative.to_string(opts)
    |> with({:ok, relative} <- ...) do
      relative
    else
      other ->
        error(date, inspect(other))
        timex_date_from_now(date)
    end
  end

  def date_from_now(object, opts) when is_map(object) or is_binary(object),
    do: date_from_pointer(object) |> date_from_now(opts)

  def date_from_now(_, _), do: nil

  def timex_date_from_now(%DateTime{} = date) do
    date
    |> Timex.format("{relative}", :relative)
    |> with({:ok, relative} <- ...) do
      relative
    else
      other ->
        error(date, inspect(other))
        nil
    end
  end

  @doc "Takes an object (or string with an ULID) and converts the ULID ID to a `DateTime` struct."
  def date_from_pointer(object) do
    with id when is_binary(id) <- Bonfire.Common.Types.ulid(object),
         {:ok, ts} <- Pointers.ULID.timestamp(id),
         {:ok, date} <- DateTime.from_unix(ts, :millisecond) do
      date
    else
      e ->
        error(e)
        nil
    end
  end

  def now(), do: DateTime.utc_now()

  def past?(%DateTime{} = dt) do
    DateTime.compare(now(), dt) == :gt
  end

  def future?(%DateTime{} = dt) do
    DateTime.compare(now(), dt) == :lt
  end
end
