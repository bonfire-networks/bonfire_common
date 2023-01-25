defmodule Bonfire.Common.DatesTimes do
  use Arrows
  import Untangle

  def date_from_now(nil), do: nil

  def date_from_now(%DateTime{} = date) do
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

  def date_from_now(object), do: date_from_pointer(object) |> date_from_now()

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
