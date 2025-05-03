defmodule Bonfire.Common.Telemetry.SystemMonitor do
  import Untangle
  use Bonfire.Common.Config

  # NOTE: see `config :os_mon` for what triggers this

  def init({_args, {:alarm_handler, alarms}}) do
    debug("Custom alarm handler init...")
    for {alarm_name, alarm_description} <- alarms, do: handle_alarm(alarm_name, alarm_description)
    {:ok, []}
  end

  def handle_event({:set_alarm, {alarm_name, alarm_description}}, state) do
    handle_alarm(alarm_name, alarm_description)
    {:ok, state}
  end

  def handle_event({:clear_alarm, {alarm_name, _alarm_description}}, state) do
    state
    |> debug("Clearing the alarm  #{alarm_name}")

    {:ok, state}
  end

  def handle_event({:clear_alarm, alarm_name}, state) do
    state
    |> debug("Clearing the alarm  #{alarm_name}")

    {:ok, state}
  end

  def handle_alarm({alarm_name, alarm_description}, []),
    do: handle_alarm(alarm_name, alarm_description)

  def handle_alarm(:disk_almost_full = alarm_name, alarm_description) do
    handle_alarm(
      "#{alarm_name} : #{alarm_description}",
      :disksup.get_disk_data()
      |> Enum.map(fn {mountpoint, kbytes, percent} ->
        "#{mountpoint} is at #{format_percent(percent)} of #{Sizeable.filesize(kbytes * 1024)}"
      end)
      |> Enum.join("\n")
    )
  end

  def handle_alarm(:process_memory_high_watermark = alarm_name, alarm_description) do
    {total, allocated, {worst_pid, worst_usage}} = :memsup.get_memory_data()
    # system_memory = :memsup.get_system_memory_data()
    # system_total = system_memory[:total_memory] || system_memory[:system_total_memory] || total

    handle_alarm(
      "#{alarm_name} : #{alarm_description}",
      "OTP memory: #{Sizeable.filesize(allocated)} allocated of #{Sizeable.filesize(total)} (highest usage by #{inspect(worst_pid)}: #{Sizeable.filesize(worst_usage)} )"
      # <>"\nSystem memory is #{format_percent(system_total/system_memory[:free_memory])} free (#{Sizeable.filesize(system_memory[:free_memory])} of #{Sizeable.filesize(system_total)})"
    )
  end

  def handle_alarm(alarm_name, alarm_description) when not is_binary(alarm_description),
    do: handle_alarm(alarm_name, inspect(alarm_description))

  def handle_alarm(alarm_name, alarm_description) do
    warn(alarm_description, "System monitor alarm: #{alarm_name}")

    case Config.get(:env) == :prod and Config.get([Bonfire.Mailer, :reply_to]) do
      false ->
        :skip

      nil ->
        warn("You need to configure an email")

      to ->
        title = "Alert: #{alarm_name}"

        Bonfire.Mailer.new(
          subject: "[System alert from Bonfire] " <> title,
          html_body:
            title <>
              "<p><pre>" <> String.replace(alarm_description, "\n", "<br/>") <> "</pre></p>",
          text_body: title <> " " <> alarm_description
        )
        |> Bonfire.Mailer.send_async(to)
    end
  end

  @doc """
  Formats percent.
  """
  def format_percent(percent) when is_float(percent), do: "#{Float.round(percent, 1)}%"
  def format_percent(nil), do: "0%"
  def format_percent(percent), do: "#{percent}%"
end
