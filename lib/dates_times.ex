defmodule Bonfire.Common.DatesTimes do
  @moduledoc """
  Date/time helpers
  """
  use Arrows
  import Untangle
  alias Bonfire.Common.Types

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

  defp timex_date_from_now(%DateTime{} = date) do
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

  def past(amount_to_remove, unit \\ :second), do: remove(now(), amount_to_remove, unit)

  def remove(dt, amount_to_remove, unit \\ :second)

  def remove(%DateTime{} = dt, amount_to_remove, unit) when is_binary(amount_to_remove),
    do: remove(dt, Types.maybe_to_integer(amount_to_remove), unit)

  def remove(%DateTime{} = dt, amount_to_remove, unit),
    do: DateTime.add(dt, -amount_to_remove, unit)

  def past?(%DateTime{} = dt) do
    DateTime.before?(dt, now())
  end

  def future?(%DateTime{} = dt) do
    DateTime.after?(dt, now())
  end
end
