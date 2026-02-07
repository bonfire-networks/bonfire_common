defmodule Bonfire.Common.Localise.POAnnotator do
  @moduledoc """
  Asynchronously patches POT files with runtime URL context in dev environment.
  Uses Expo library for reliable POT file parsing and composition.
  """

  use GenServer
  import Untangle
  use Bonfire.Common.Config

  # Configuration for max URLs per entry
  @default_max_urls 4
  # 5 seconds
  @after_seconds_inactivity 5000
  @comment_prefix " URLs: "

  # Helper to patch POT files with runtime URL context (dev only)
  def maybe_patch_pot_with_url_ast(msgid, domain, file, line) do
    if Config.env() == :dev and Config.get(:patch_pot_with_urls, true) do
      quote do
        case Bonfire.Common.Localise.POAnnotator.get_process_current_url() do
          nil ->
            :ok

          url ->
            Bonfire.Common.Localise.POAnnotator.patch_async(
              unquote(msgid),
              unquote(domain),
              unquote(file),
              unquote(line),
              url
            )
        end
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Helper to get current URL from runtime context
  """
  def get_process_current_url do
    Process.get(:bonfire_current_url)
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Asynchronously patches POT file with URL context.
  """
  def patch_async(msgid, domain, file, line, url) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:patch_url, msgid, domain, file, line, url})
    end

    :ok
  end

  # GenServer callbacks

  def init(_) do
    {:ok,
     %{
       # pot_file => %Expo.Messages{}
       parsed_cache: %{},
       # pot_file => MapSet of {msgid, file, line}
       lookup_cache: %{},
       # pot_file => timer_ref
       pending_writes: %{},
       # Track which files have changes pending
       dirty_files: MapSet.new()
     }}
  end

  def handle_cast({:patch_url, msgid, domain, file, line, url}, state) do
    pot_file =
      determine_pot_file(domain)

    # Normalize the file path to match what's in POT files
    relative_file = normalize_file_path(file)
    entry_key = {msgid, relative_file, line}

    # Ensure file is loaded and parsed
    case ensure_file_parsed(pot_file, state) do
      {:ok, new_state} ->
        # Check if this entry exists
        lookup = Map.get(new_state.lookup_cache, pot_file, MapSet.new())

        if MapSet.member?(lookup, entry_key) do
          # Entry exists, check if URL needs to be added/updated
          case update_entry_url_if_changed(new_state, pot_file, msgid, relative_file, line, url) do
            {:changed, updated_state} ->
              # Only schedule write if something actually changed
              schedule_write(pot_file)
              dirty_files = MapSet.put(updated_state.dirty_files, pot_file)
              {:noreply, %{updated_state | dirty_files: dirty_files}}

            {:unchanged, unchanged_state} ->
              # No changes needed
              {:noreply, unchanged_state}
          end
        else
          # Entry doesn't exist yet (maybe new translation)
          warn(
            "You might want to run `just mix gettext.extract` as an entry was not found: \"#{msgid}\" at #{url} from #{relative_file}:#{line} in POT file #{pot_file}"
          )

          {:noreply, new_state}
        end

      {:error, reason} ->
        warn(reason, "Failed to parse POT file: #{pot_file}")
        {:noreply, state}
    end
  end

  # Add this new function to normalize file paths
  defp normalize_file_path(file) do
    # Convert absolute path to relative, and handle extensions subdirectory
    relative = Path.relative_to_cwd(file)

    # Remove "extensions/{extension_name}/" prefix if present
    case String.split(relative, "/", parts: 3) do
      ["extensions", _extension_name, rest] -> rest
      _ -> relative
    end
  end

  def handle_info({:write_file, pot_file}, state) do
    # Only write if file is actually dirty
    if MapSet.member?(state.dirty_files, pot_file) do
      case Map.get(state.parsed_cache, pot_file) do
        %Expo.Messages{} = messages ->
          Task.start(fn ->
            try do
              content =
                Expo.PO.compose(messages)

              File.write!(pot_file, content)
            rescue
              e ->
                warn(e, "Failed to write POT file #{pot_file}")
            end
          end)

        _ ->
          warn(pot_file, "No parsed messages foun in POT file, cannot write")
      end

      # Remove from dirty files
      dirty_files = MapSet.delete(state.dirty_files, pot_file)
      state = %{state | dirty_files: dirty_files}
    end

    # Remove from pending writes
    pending_writes = Map.delete(state.pending_writes, pot_file)
    {:noreply, %{state | pending_writes: pending_writes}}
  end

  # Private functions

  defp determine_pot_file(""), do: "priv/localisation/default.po"

  defp determine_pot_file(domain) when is_binary(domain) do
    "priv/localisation/#{domain}.po"
  end

  defp determine_pot_file(_), do: "priv/localisation/default.po"

  defp ensure_file_parsed(pot_file, state) do
    case Map.get(state.parsed_cache, pot_file) do
      nil ->
        # Load and parse file using Expo
        case load_pot_file_with_expo(pot_file) do
          {:ok, messages} ->
            # Build lookup cache for fast entry existence checks
            lookup = build_lookup_cache(messages)

            parsed_cache = Map.put(state.parsed_cache, pot_file, messages)
            lookup_cache = Map.put(state.lookup_cache, pot_file, lookup)

            {:ok, %{state | parsed_cache: parsed_cache, lookup_cache: lookup_cache}}

          error ->
            error
        end

      _messages ->
        # Already parsed
        {:ok, state}
    end
  end

  defp load_pot_file_with_expo(pot_file) do
    case Expo.PO.parse_file(pot_file) do
      {:ok, messages} ->
        {:ok, messages}

      {:error, :enoent} ->
        # File doesn't exist, create empty structure
        {:ok, %Expo.Messages{messages: [], headers: []}}

      {:error, error} ->
        error(error, "Failed to parse POT file: #{pot_file}")
    end
  end

  defp build_lookup_cache(%Expo.Messages{messages: messages}) do
    messages
    |> Enum.flat_map(fn message ->
      case message do
        %Expo.Message.Singular{msgid: msgid_parts, references: references} ->
          msgid = IO.iodata_to_binary(msgid_parts)
          build_lookup_keys(msgid, references)

        %Expo.Message.Plural{msgid: msgid_parts, references: references} ->
          msgid = IO.iodata_to_binary(msgid_parts)
          build_lookup_keys(msgid, references)

        _ ->
          []
      end
    end)
    |> MapSet.new()
  end

  defp build_lookup_keys(msgid, references) do
    try do
      references
      |> Enum.map(fn
        {file, line} -> {msgid, file, line}
        [{file, line}] -> {msgid, file, line}
      end)
    rescue
      e ->
        warn(
          e,
          "Failed to build lookup keys for msgid '#{msgid}' with references: #{inspect(references)}"
        )

        []
    end
  end

  defp update_entry_url_if_changed(state, pot_file, msgid, file, line, url) do
    case Map.get(state.parsed_cache, pot_file) do
      %Expo.Messages{messages: messages} = expo_messages ->
        # Find the matching message and check if it needs updating
        {updated_messages, changed?} =
          Enum.map_reduce(messages, false, fn message, acc_changed ->
            case message do
              %Expo.Message.Singular{msgid: msgid_parts, references: references} = msg ->
                current_msgid = IO.iodata_to_binary(msgid_parts)

                # Check if this message matches our target
                if current_msgid == msgid and
                     Enum.any?(references, fn
                       {ref_file, ref_line} ->
                         ref_file == file and ref_line == line

                       [{ref_file, ref_line}] ->
                         ref_file == file and ref_line == line
                     end) do
                  # Check if URL comment needs updating
                  case update_url_comments_if_needed(msg.extracted_comments, url) do
                    {:changed, updated_comments} ->
                      updated_msg = %{msg | extracted_comments: updated_comments}
                      {updated_msg, true}

                    {:unchanged, _} ->
                      {msg, acc_changed}
                  end
                else
                  {msg, acc_changed}
                end

              %Expo.Message.Plural{msgid: msgid_parts, references: references} = msg ->
                current_msgid = IO.iodata_to_binary(msgid_parts)

                # Check if this plural message matches our target
                if current_msgid == msgid and
                     Enum.any?(references, fn
                       {ref_file, ref_line} ->
                         ref_file == file and ref_line == line

                       [{ref_file, ref_line}] ->
                         ref_file == file and ref_line == line
                     end) do
                  # Check if URL comment needs updating
                  case update_url_comments_if_needed(msg.extracted_comments, url) do
                    {:changed, updated_comments} ->
                      updated_msg = %{msg | extracted_comments: updated_comments}
                      {updated_msg, true}

                    {:unchanged, _} ->
                      {msg, acc_changed}
                  end
                else
                  {msg, acc_changed}
                end

              _ ->
                {message, acc_changed}
            end
          end)

        if changed? do
          updated_expo_messages = %{expo_messages | messages: updated_messages}
          parsed_cache = Map.put(state.parsed_cache, pot_file, updated_expo_messages)
          {:changed, %{state | parsed_cache: parsed_cache}}
        else
          {:unchanged, state}
        end

      _ ->
        {:unchanged, state}
    end
  end

  defp update_url_comments_if_needed(extracted_comments, new_url)
       when is_list(extracted_comments) and extracted_comments != [] do
    max_urls = Config.get(:pot_max_urls_per_entry, @default_max_urls)
    url_prefix = Config.get(:pot_url_prefix, "")

    new_url = "#{url_prefix}#{new_url}"

    # Find existing URL comment line
    {url_comment_lines, other_comments} =
      Enum.split_with(extracted_comments, &String.starts_with?(&1, @comment_prefix))

    # Extract existing URLs from the single URL comment line
    existing_urls =
      case url_comment_lines do
        [] ->
          []

        [url_line] ->
          url_line
          |> String.replace_prefix(@comment_prefix, "")
          |> String.split(" ")
          |> Enum.reject(&(&1 == ""))

        # If somehow there are multiple URL comment lines, merge them
        multiple_lines ->
          multiple_lines
          |> Enum.flat_map(fn line ->
            line
            |> String.replace_prefix(@comment_prefix, "")
            |> String.split(" ")
            |> Enum.reject(&(&1 == ""))
          end)
      end

    # Check if new URL is already present
    if length(existing_urls) == max_urls or new_url in existing_urls do
      # URL already exists, no change needed
      {:unchanged, extracted_comments}
    else
      do_update_urls(other_comments, [new_url | existing_urls], max_urls)
    end
  end

  defp update_url_comments_if_needed(_extracted_comments, new_url) do
    max_urls = Config.get(:pot_max_urls_per_entry, @default_max_urls)
    url_prefix = Config.get(:pot_url_prefix, "")

    new_url = "#{url_prefix}#{new_url}"

    do_update_urls([], [new_url], max_urls)
  end

  defp do_update_urls(other_comments, urls, max_urls) do
    # Add new URL, respecting max limit
    updated_urls =
      urls
      |> Enum.uniq()
      |> Enum.take(max_urls)

    # Create single URL comment line
    url_comment =
      @comment_prefix <> Enum.join(updated_urls, " ")

    # Combine with other comments (URL comment first)
    updated_comments = [url_comment | other_comments]

    {:changed, updated_comments}
  end

  # Debounce writes - only write after X seconds of no activity
  defp schedule_write(pot_file, after_seconds_inactivity \\ @after_seconds_inactivity) do
    case Process.get({:write_timer, pot_file}) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end

    timer_ref = Process.send_after(self(), {:write_file, pot_file}, after_seconds_inactivity)
    Process.put({:write_timer, pot_file}, timer_ref)
  end
end
