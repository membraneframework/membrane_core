defmodule Membrane.Core.Element.AtomicDemand.DistributedAtomic.Worker do
  @moduledoc false

  # This is a GenServer created when the counter is about to be accessed from different nodes - it's running on the same node,
  # where the :atomics variable is put, and processes from different nodes can ask it to modify the counter on their behalf.

  use GenServer

  @type t :: pid()

  @spec start_link(any()) :: {:ok, t}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
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
end
