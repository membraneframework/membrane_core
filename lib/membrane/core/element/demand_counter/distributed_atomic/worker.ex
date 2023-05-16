defmodule Membrane.Core.Element.DemandCounter.DistributedAtomic.Worker do
  @moduledoc false

  # This is a GenServer created when the counter is about to be accessed from different nodes - it's running on the same node,
  # where the :atomics variable is put, and processes from different nodes can ask it to modify the counter on their behalf.

  use GenServer

  @type t :: pid()

  @spec start_link(pid()) :: {:ok, t}
  def start_link(owner_pid), do: GenServer.start_link(__MODULE__, owner_pid)

  @impl true
  def init(owner_pid) do
    ref = Process.monitor(owner_pid)
    {:ok, %{ref: ref}, :hibernate}
  end

  @impl true
  def handle_call({:add_get, atomic_ref, value}, _from, _state) do
    result = :atomics.add_get(atomic_ref, 1, value)
    {:reply, result, nil}
  end

  @impl true
  def handle_call({:sub_get, atomic_ref, value}, _from, _state) do
    result = :atomics.sub_get(atomic_ref, 1, value)
    {:reply, result, nil}
  end

  @impl true
  def handle_call({:get, atomic_ref}, _from, _state) do
    result = :atomics.get(atomic_ref, 1)
    {:reply, result, nil}
  end

  @impl true
  def handle_cast({:put, atomic_ref, value}, _state) do
    :atomics.put(atomic_ref, 1, value)
    {:noreply, nil}
  end

  @impl true
  def handle_info({:DOWN, ref, _process, _pid, _reason}, %{ref: ref} = state) do
    {:stop, :normal, state}
  end
end
