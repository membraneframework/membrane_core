defmodule Membrane.Core.Element.DemandCounter.Worker do
  @moduledoc false

  # This is a GenServer created when the counter is about to be accessed from different nodes - it's running on the same node,
  # where the :atomics variable is put, and processes from different nodes can ask it to modify the counter on their behalf.

  use GenServer

  @type t :: pid()

  @spec start(pid()) :: {:ok, t}
  def start(parent_pid), do: GenServer.start(__MODULE__, parent_pid)

  @impl true
  def init(parent_pid) do
    Process.monitor(parent_pid)
    {:ok, nil, :hibernate}
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
  def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
    {:stop, :normal, state}
  end
end
