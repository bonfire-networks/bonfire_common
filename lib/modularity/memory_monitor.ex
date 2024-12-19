defmodule Bonfire.Common.MemoryMonitor do
  @moduledoc """
  This module implements a GenServer that monitors the memory usage of a process.
  It periodically checks the memory consumption.
  """

  use GenServer
  require Logger

  @time_to_check :timer.seconds(10)

  @doc """
  Starts the MemoryMonitor process linked to the caller process with given options.
  """
  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(name, pid_to_monitor \\ self()) do
    GenServer.start_link(__MODULE__, {name, pid_to_monitor})
  end

  @impl GenServer
  @spec init(pid) :: {:ok, pid}
  def init({name, pid}) do
    Process.send_after(self(), :check, @time_to_check)
    Process.monitor(pid)

    {:ok, {0, {name, pid}}}
  end

  @doc """
  Handles incoming messages to the GenServer.
    - `:check` - Performs memory usage checks on the monitored process
  """
  @impl GenServer
  def handle_info(:check, {_, {name, pid_to_monitor}}) do
    Process.send_after(self(), :check, @time_to_check)

    memory_used = get_memory_usage(name, pid_to_monitor)

    {:noreply, {memory_used, {name, pid_to_monitor}}}
  end

  # when the monitored process dies, die
  def handle_info({:DOWN, _ref, :process, pid, _}, {_, {_, pid}}), do: {:stop, :normal, nil}

  @spec get_memory_usage(pid) :: non_neg_integer
  def get_memory_usage(name, pid \\ self()) do
    processes_tree = get_processes_tree(pid, MapSet.new([]))
    {bin_mem_size, _} = get_bin_memory(processes_tree)
    process_mem_size = get_heap_memory(processes_tree)
    total = bin_mem_size + process_mem_size

    Logger.info(
      "#{Sizeable.filesize(total)} of memory used by #{name} (#{Enum.count(processes_tree[:links] || [])} processes under #{inspect(pid)}) #{Sizeable.filesize(process_mem_size)} by processes and #{Sizeable.filesize(bin_mem_size)} by binaries"
    )

    total
  end

  @spec get_processes_tree(pid | port, MapSet.t()) :: map
  defp get_processes_tree(pid, used_pids) when is_pid(pid) do
    if MapSet.member?(used_pids, pid),
      do: nil,
      else: do_get_processes_tree(pid, used_pids)
  end

  # the linked resource may be a port, not a pid
  defp get_processes_tree(_, _), do: nil

  @spec do_get_processes_tree(pid | port, MapSet.t()) :: map
  defp do_get_processes_tree(pid, used_pids) when is_pid(pid) do
    used_pids = MapSet.put(used_pids, pid)

    {process_extra_info, process_info} =
      pid
      |> Process.info([:dictionary, :current_function, :status, :links, :memory, :binary])
      |> Keyword.split([:dictionary, :current_function, :status])

    if child?(process_extra_info, used_pids) || MapSet.size(used_pids) == 1 do
      process_info
      |> Map.new()
      |> Map.update(:links, [], &get_allowed_processes(&1, used_pids))
    else
      nil
    end
  end

  @spec get_allowed_processes(pid, MapSet.t()) :: [map]
  defp get_allowed_processes(pids, used_pids) do
    pids
    |> Enum.map(&get_processes_tree(&1, used_pids))
    |> Enum.reject(&is_nil/1)
  end

  @spec get_bin_memory(map, {integer, MapSet.t()}) :: {integer, MapSet.t()}
  defp get_bin_memory(
         %{binary: binaries, links: links},
         {mem_used, used_bin_refs} \\ {0, MapSet.new([])}
       ) do
    {bin_mem, used_bin_refs} = Enum.reduce(binaries, {mem_used, used_bin_refs}, &maybe_sum/2)
    Enum.reduce(links, {bin_mem, used_bin_refs}, &get_bin_memory/2)
  end

  @spec maybe_sum({integer, integer, integer}, {integer, MapSet.t()}) :: {integer, MapSet.t()}
  defp maybe_sum({bin_ref, mem, _}, {total_mem, used_bin_refs}) do
    if MapSet.member?(used_bin_refs, bin_ref),
      do: {total_mem, used_bin_refs},
      else: {total_mem + mem, MapSet.put(used_bin_refs, bin_ref)}
  end

  @spec get_heap_memory(map) :: integer
  defp get_heap_memory(%{memory: mem, links: links}) do
    links
    |> Enum.map(&get_heap_memory/1)
    |> Enum.sum()
    |> Kernel.+(mem)
  end

  @spec child?(keyword, MapSet.t()) :: boolean
  defp child?(process_extra_info, used_pids) do
    dictionary = Keyword.get(process_extra_info, :dictionary)
    status = Keyword.get(process_extra_info, :status)
    {module, _, _} = Keyword.get(process_extra_info, :current_function)
    parents = get_parents(dictionary)
    # if it's Task.asyn_stream monitoring process, then its status is :waiting
    !MapSet.disjoint?(parents, used_pids) || (module == Task.Supervised && status == :waiting)
  end

  @spec get_parents(keyword) :: MapSet.t()
  defp get_parents(dictionary) do
    ancestors = Keyword.get(dictionary, :"$ancestors", [])
    callers = Keyword.get(dictionary, :"$callers", [])
    MapSet.new(ancestors ++ callers)
  end
end
