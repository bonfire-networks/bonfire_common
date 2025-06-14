defmodule Bonfire.Common.DatesTimes do
  @moduledoc """
  Date/time helpers
  """
  # use Arrows
  use Bonfire.Common.Localise
  import Untangle
  alias Bonfire.Common.Types

  # (2 ^ 48) - 1
  @max_unix_time 281_474_976_710_655

  @doc """
  Takes a ULID ID (or an object with one) or a `DateTime` struct, and turns the date into a relative phrase, e.g. `2 days ago`.

  ## Examples

      > date_from_now(%{id: "01FJ6G6V9E7Y3A6HZ5F2M3K4RY"})
      "25 days ago"  # Example output

      > date_from_now("01FJ6G6V9E7Y3A6HZ5F2M3K4RY")
      "25 days ago"  # Example output
  """
  def date_from_now(ulid_or_date, opts \\ []) do
    case to_date_time(ulid_or_date) do
      nil ->
        nil

      date_time ->
        relative_date(date_time, opts)
    end
  end

  @doc """
  Converts a `DateTime` struct to a relative date string. Uses `Cldr.DateTime` or `Timex` libraries.

  ## Examples

      iex> relative_date(DateTime.now!("Etc/UTC"))
      "now"  # Example output
  """
  def relative_date(date_time, opts \\ []) do
    case Bonfire.Common.Localise.Cldr.DateTime.Relative.to_string(date_time, opts) do
      {:ok, "-" <> relative_date} ->
        # Cldr narrow format uses minus for past dates, convert to "ago" format
        l("%{relative_date} ago", relative_date: relative_date)

      {:ok, relative} ->
        relative

      {:error, other} ->
        # Fallback to Timex if Cldr fails
        error(date_time, inspect(other))
        timex_date_from_now(date_time)

      other ->
        error(other, inspect(date_time))
        timex_date_from_now(date_time)
    end
  end

  @doc """
  Formats a `DateTime` struct or date into a string using `Cldr.DateTime.to_string/2`.

  ## Examples

      > format(DateTime.now!("Etc/UTC"))
      "Jul 25, 2024, 11:08:21 AM"
  """
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

  @doc """
  Formats a `Date` struct or date into a string using `Cldr.Date.to_string/2`.

  ## Examples

      > format_date(DateTime.now!("Etc/UTC"))
      "Jul 25, 2024"

      iex> format_date("2024-07-25")
      "Jul 25, 2024"

      iex> format_date("2024-7-25")
      "Jul 25, 2024"

      iex> format_date("2024-7")
      "Jul, 2024" # TODO
  """
  def format_date(date, opts \\ []) do
    case to_date(date) |> debug("format_date") do
      nil ->
        # Special case for partial dates
        if is_binary(date) && Regex.match?(~r/^\d{4}-\d{1,2}$/, date) do
          # Handle YYYY-MM format
          parts = String.split(date, "-")
          year = Enum.at(parts, 0)
          month = Enum.at(parts, 1) |> String.to_integer()
          "#{month_name(month) || month}, #{year}"
        else
          error(date, "Could not format date")
          nil
        end

      date ->
        case Bonfire.Common.Localise.Cldr.Date.to_string(date, opts) do
          {:ok, formatted} ->
            formatted

          other ->
            error(other, "Could not format date")
        end
    end
  end

  # Helper function to get month name
  defp month_name(month) when month in 1..12 do
    [
      l("Jan"),
      l("Feb"),
      l("Mar"),
      l("Apr"),
      l("May"),
      l("Jun"),
      l("Jul"),
      l("Aug"),
      l("Sep"),
      l("Oct"),
      l("Nov"),
      l("Dec")
    ]
    |> Enum.at(month - 1)
  end

  defp month_name(_), do: nil

  @doc """
  Returns a list of available format keys for the given locale.

  ## Examples

      > available_format_keys()
      [:short, :medium, :long, :full]  # Example output
  """
  def available_format_keys(scope \\ DateTime, locale \\ Cldr.get_locale())

  def available_format_keys(scope, locale) do
    available_formats(scope, locale)
    |> Keyword.keys()
  end

  @doc """
  Returns a keyword list of available date/time formats for the given locale.

  ## Examples

      > available_formats()
      [short: "Short", medium: "Medium", long: "Long", full: "Full"]  # Example output
  """
  def available_formats(scope \\ DateTime, locale \\ Cldr.get_locale())

  def available_formats(DateTime, locale) do
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
          []
      end
    )
  end

  def available_formats(Date, locale) do
    Keyword.merge(
      [short: l("Short"), medium: l("Medium"), long: l("Long"), full: l("Full")],
      with {:ok, formats} <- Cldr.Date.available_formats(locale) |> Keyword.new() do
        formats
      else
        e ->
          error(e)
          []
      end
    )
  end

  @doc """
  Converts various formats into a `DateTime` struct.

  ## Examples

      > to_date_time(%Date{year: 2024, month: 7, day: 25})
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output

      > to_date_time("2024-07-25")
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output

      > to_date_time(1656115200000)
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output

      > to_date_time(%{"day" => 25, "month" => 7, "year" => 2024})
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output
  """
  def to_date_time(%DateTime{} = date_time) do
    date_time
  end

  def to_date_time(%Date{} = date) do
    with {:ok, datetime} <- DateTime.new(date, Time.new!(0, 0, 0)) do
      datetime
    else
      e ->
        error(e, "not a valid date")
        nil
    end
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
    if Types.is_uid?(string) do
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

  def to_date_time(%{"day" => day, "month" => month, "year" => year})
      when is_number(year) or is_binary(year) do
    with {:ok, date} <-
           Date.new(
             Types.maybe_to_integer(year),
             Types.maybe_to_integer(month) || 1,
             Types.maybe_to_integer(day) || 1
           ) do
      to_date_time(date)
    else
      e ->
        error(e, "not a valid date")
        nil
    end
  end

  def to_date_time(%{} = object),
    do: date_from_pointer(object)

  def to_date_time(_), do: nil

  @doc """
  Converts various formats into a `DateTime` struct.

  ## Examples

      iex> to_date(%Date{year: 2024, month: 7, day: 25})
      %Date{year: 2024, month: 7, day: 25} 

      iex> to_date("2024-07-25")
      %Date{year: 2024, month: 7, day: 25}

      iex> to_date("2024-7-25")
      %Date{year: 2024, month: 7, day: 25}

      iex> to_date(1656115200000)
      %Date{year: 2022, month: 6, day: 25}  

      iex> to_date(%{"day" => 25, "month" => 7, "year" => 2024})
      %Date{year: 2024, month: 7, day: 25}  
  """
  def to_date(%Date{} = date) do
    date
  end

  def to_date(%DateTime{} = date_time) do
    DateTime.to_date(date_time)
  end

  def to_date(ts) when is_integer(ts) do
    with {:ok, date} <- DateTime.from_unix(ts, :millisecond) do
      date
      |> to_date()
    else
      e ->
        error(e, "not a valid timestamp")
        nil
    end
  end

  def to_date(string) when is_binary(string) and byte_size(string) == 10 do
    case Date.from_iso8601(string) do
      {:ok, date} ->
        date

      other ->
        error(other, "Invalid date format")
        nil
    end
  end

  def to_date(string) when is_binary(string) do
    if Types.is_uid?(string) do
      date_from_pointer(string)
      |> to_date()
    else
      case string
           |> String.trim("/")
           |> Date.from_iso8601() do
        {:ok, datetime, 0} ->
          datetime

        other ->
          if Regex.match?(~r/^\d{4}-\d{1,2}-\d{1,2}$/, string) do
            # Parse non-standard format dates
            [year_str, month_str, day_str] = String.split(string, "-")
            year = String.to_integer(year_str)
            month = String.to_integer(month_str)
            day = String.to_integer(day_str)

            case Date.new(year, month, day) do
              {:ok, date} ->
                date

              error ->
                error(error, "Invalid date format")
                nil
            end
          else
            error(other, "Unsupported date format")
            nil
          end
      end
    end
  end

  def to_date(%{
        "day" => %{"value" => day},
        "month" => %{"value" => month},
        "year" => %{"value" => year}
      }),
      do: to_date(%{"day" => day, "month" => month, "year" => year})

  def to_date(%{"day" => day, "month" => month, "year" => year})
      when is_number(year) or is_binary(year) do
    with {:ok, date} <-
           Date.new(
             Types.maybe_to_integer(year),
             Types.maybe_to_integer(month) || 1,
             Types.maybe_to_integer(day) || 1
           ) do
      date
    else
      e ->
        error(e, "not a valid date")
        nil
    end
  end

  def to_date(%{id: id}) when is_binary(id),
    do:
      date_from_pointer(id)
      |> to_date()

  def to_date(%{} = object),
    do:
      date_from_pointer(object)
      |> to_date()

  def to_date(other) do
    warn(other, "not supported")
  end

  defp timex_date_from_now(%DateTime{} = date) do
    with {:ok, relative} <- Timex.format(date, "{relative}", :relative) do
      relative
    else
      other ->
        error(date, inspect(other))
        nil
    end
  end

  @doc """
  Takes an object (or string with an ULID) and converts the ULID ID to a `DateTime` struct.

  ## Examples

      > date_from_pointer("01FJ6G6V9E7Y3A6HZ5F2M3K4RY")
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output
  """
  def date_from_pointer(object) do
    with id when is_binary(id) <- Bonfire.Common.Types.uid(object),
         {:ok, ts} <- Needle.ULID.timestamp(id) do
      to_date_time(ts)
    else
      e ->
        error(e)
        nil
    end
  end

  @doc """
  Generates a ULID based on a `DateTime` or a string representation of a date/time, but only if the date/time is in the past.

  ## Examples

      > generate_ulid_if_past(%Date{year: 2024, month: 7, day: 25})
      "01J3KJZZ00X1EXD6TZYD3PPDR6"  # Example output

      > generate_ulid_if_past("2024-07-25")
      "01J3KJZZ00X1EXD6TZYD3PPDR6"  # Example output
  """
  def generate_ulid_if_past(date_time_or_string) do
    with %DateTime{} = date_time <-
           to_date_time(date_time_or_string),
         # only if published in the past
         :lt <-
           DateTime.compare(date_time, DateTime.now!("Etc/UTC")) do
      date_time
      # |> debug("date_time")
      |> generate_ulid()
    else
      other ->
        debug(other, "skip")
        nil
    end
  end

  @doc """
  Generates a ULID based on a `DateTime` or a string representation of a date/time.

  ## Examples

      > generate_ulid(%Date{year: 2024, month: 7, day: 25})
      "01J3KJZZ00X1EXD6TZYD3PPDR6"  # Example output

      > generate_ulid("2050-01-31")
      "01J3KJZZ00X1EXD6TZYD3PPDR6"  # Example output
  """
  def generate_ulid(timestamp) when is_integer(timestamp) and timestamp > 281_474_976_710_655 do
    warn(timestamp, "tried to go too far into the future, defaulting to the year 2038")
    Needle.UID.generate(281_474_976_710_655)
  end

  def generate_ulid(timestamp) when is_integer(timestamp) and timestamp < 0 do
    warn(timestamp, "tried to go too far into the past, defaulting to the year 1970")
    Needle.UID.generate(0)
  end

  def generate_ulid(timestamp) when is_integer(timestamp) do
    timestamp
    |> Needle.UID.generate()
  end

  def generate_ulid(%DateTime{year: year} = date_time) when year > 2037 do
    warn(date_time, "tried to go too far into the future, defaulting to the year 2038")
    Needle.UID.generate(281_474_976_710_655)
  end

  def generate_ulid(%DateTime{} = date_time) do
    date_time
    |> DateTime.to_unix(:millisecond)
    # |> debug("to_unix")
    |> generate_ulid()
  end

  def generate_ulid(date_time_string) when is_binary(date_time_string) do
    with %DateTime{} = date_time <-
           to_date_time(date_time_string) do
      date_time
      # |> debug("date_time")
      |> generate_ulid()
    end
  end

  @doc """
  Returns the current UTC `DateTime`.

  ## Examples

      > now()
      %DateTime{year: 2024, month: 7, day: 25, ...}  # Example output
  """
  def now(), do: DateTime.utc_now()

  @doc """
  Returns a `DateTime` in the past, relative to the current time, by subtracting a specified amount of time.

  ## Examples

      > past(10, :day)
      %DateTime{year: 2024, month: 7, day: 15, ...}  # Example output
  """
  def past(amount_to_remove, unit \\ :second), do: remove(now(), amount_to_remove, unit)

  @doc """
  Removes a specified amount of time from a `DateTime`.

  ## Examples

      > remove(%Date{year: 2024, month: 7, day: 25}, 10, :day)
      %DateTime{year: 2024, month: 7, day: 15, ...}  # Example output
  """
  def remove(dt, amount_to_remove, unit \\ :second)

  def remove(%DateTime{} = dt, amount_to_remove, unit) when is_binary(amount_to_remove),
    do: remove(dt, Types.maybe_to_integer(amount_to_remove), unit)

  # for compat with elixir 1.13
  def remove(%DateTime{} = dt, amount_to_remove, :day),
    do: remove(dt, amount_to_remove * 24 * 60 * 60, :second)

  def remove(%DateTime{} = dt, amount_to_remove, unit),
    do: DateTime.add(dt, -amount_to_remove, unit)

  @doc """
  Checks if a `DateTime` is in the past relative to the current time.

  ## Examples

      iex> past?(%Date{year: 3020, month: 7, day: 25})
      false  # Example output

      iex> past?(%Date{year: 2023, month: 7, day: 24})
      true   # Example output
  """
  def past?(%DateTime{} = dt) do
    DateTime.before?(dt, now())
  end

  def past?(%Date{} = dt) do
    Date.before?(dt, now())
  end

  @doc """
  Checks if a `DateTime` is in the future relative to the current time.

  ## Examples

      iex> future?(%Date{year: 3020, month: 7, day: 25})
      true  # Example output

      iex> future?(%Date{year: 2023, month: 7, day: 25})
      false  # Example output
  """
  def future?(%DateTime{} = dt) do
    DateTime.after?(dt, now())
  end

  def future?(%Date{} = dt) do
    Date.after?(dt, now())
  end

  def format_duration(duration) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _} -> format_duration(seconds)
      :error -> duration
    end
  end

  def format_duration(seconds) when is_number(seconds) do
    total_minutes = trunc(seconds / 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)
    remaining_seconds = seconds - total_minutes * 60

    cond do
      hours > 0 -> "#{hours}h #{minutes}min"
      minutes > 0 -> "#{minutes}min"
      true -> "#{Float.round(Types.maybe_to_float(remaining_seconds), 2)}s"
    end
  end
end
