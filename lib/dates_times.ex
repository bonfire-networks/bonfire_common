defmodule Bonfire.Common.DatesTimes do
  @moduledoc """
  Date/time helpers
  """
  use Arrows
  use Bonfire.Common.Localise
  import Untangle
  alias Bonfire.Common.Types

  @doc "Takes a ULID ID (or an object with one) or a `DateTime` struct, and turns the date into a relative phrase, e.g. `2 days ago`, using the `Cldr.DateTime` or `Timex` library."
  def date_from_now(ulid_or_date, opts \\ []) do
    case to_date_time(ulid_or_date) do
      nil ->
        nil

      date_time ->
        relative_date(date_time, opts)
    end
  end

  def relative_date(date_time, opts \\ []) do
    date_time
    |> Bonfire.Common.Localise.Cldr.DateTime.Relative.to_string(opts)
    |> with({:ok, relative} <- ...) do
      relative
    else
      other ->
        error(date_time, inspect(other))
        timex_date_from_now(date_time)
    end
  end

  def format(date, opts \\ []) do
    case to_date_time(date) do
      nil ->
        nil

      date ->
        case Bonfire.Common.Localise.Cldr.DateTime.to_string(date, opts) do
          {:ok, formatted} ->
            formatted

          other ->
            error(other)
            nil
        end
    end
  end

  def available_format_keys(locale \\ Cldr.get_locale()) do
    available_formats(locale)
    |> Keyword.keys()
  end

  def available_formats(locale \\ Cldr.get_locale()) do
    Keyword.merge(
      [short: l("Short"), medium: l("Medium"), long: l("Long"), full: l("Full")],
      with {:ok, formats} <- Cldr.DateTime.Format.date_time_available_formats(locale) do
        formats
        |> Enum.map(fn
          {key, %{one: str}} -> {key, str}
          {key, %{unicode: str}} -> {key, str}
          {key, %{ascii: str}} -> {key, str}
          #  just in case
          {key, %{} = map} -> {key, Enum.at(map, 0) |> elem(1)}
          {key, str} -> {key, str}
        end)
      else
        e ->
          error(e)
          %{}
      end
    )
  end

  def to_date_time(%DateTime{} = date_time) do
    date_time
  end

  def to_date_time(%Date{} = date) do
    date
    |> DateTime.new!(Time.new!(0, 0, 0))
  end

  def to_date_time(ts) when is_integer(ts) do
    with {:ok, date} <- DateTime.from_unix(ts, :millisecond) do
      date
    else
      e ->
        error(e, "not a valid timestamp")
        nil
    end
  end

  def to_date_time(string) when is_binary(string) and byte_size(string) == 10 do
    case Date.from_iso8601(string) do
      {:ok, date} ->
        to_date_time(date)

      other ->
        error(other)
        nil
    end
  end

  def to_date_time(string) when is_binary(string) do
    if Types.is_ulid?(string) do
      date_from_pointer(string)
    else
      case string
           |> String.trim("/")
           |> DateTime.from_iso8601() do
        {:ok, datetime, 0} ->
          datetime

        other ->
          error(other)
          nil
      end
    end
  end

  def to_date_time(%{id: id}) when is_binary(id),
    do: date_from_pointer(id)

  def to_date_time(%{
        "day" => %{"value" => day},
        "month" => %{"value" => month},
        "year" => %{"value" => year}
      }),
      do: to_date_time(%{"day" => day, "month" => month, "year" => year})

  def to_date_time(%{"day" => day, "month" => month, "year" => year}),
    do:
      Date.new(
        Types.maybe_to_integer(year),
        Types.maybe_to_integer(month),
        Types.maybe_to_integer(day)
      )
      ~> to_date_time()

  def to_date_time(%{} = object),
    do: date_from_pointer(object)

  def to_date_time(_), do: nil

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
         {:ok, ts} <- Needle.ULID.timestamp(id) do
      to_date_time(ts)
    else
      e ->
        error(e)
        nil
    end
  end

  def maybe_generate_ulid(date_time_or_string) do
    with %DateTime{} = date_time <-
           to_date_time(date_time_or_string) |> debug("date"),
         # only if published in the past
         :lt <-
           DateTime.compare(date_time, DateTime.now!("Etc/UTC")) do
      date_time
      # |> debug("date_time")
      |> DateTime.to_unix(:millisecond)
      # |> debug("to_unix")
      |> Needle.ULID.generate()
    else
      other ->
        debug(other, "skip")
        nil
    end
  end

  def now(), do: DateTime.utc_now()

  def past(amount_to_remove, unit \\ :second), do: remove(now(), amount_to_remove, unit)

  def remove(dt, amount_to_remove, unit \\ :second)

  def remove(%DateTime{} = dt, amount_to_remove, unit) when is_binary(amount_to_remove),
    do: remove(dt, Types.maybe_to_integer(amount_to_remove), unit)

  # for compat with elixir 1.13
  def remove(%DateTime{} = dt, amount_to_remove, :day),
    do: remove(dt, amount_to_remove * 24 * 60 * 60, :second)

  def remove(%DateTime{} = dt, amount_to_remove, unit),
    do: DateTime.add(dt, -amount_to_remove, unit)

  def past?(%DateTime{} = dt) do
    DateTime.before?(dt, now())
  end

  def future?(%DateTime{} = dt) do
    DateTime.after?(dt, now())
  end
end
