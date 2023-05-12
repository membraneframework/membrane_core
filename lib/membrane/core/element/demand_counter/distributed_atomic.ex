defmodule Membrane.Core.Element.DemandCounter.DistributedAtomic do
  @moduledoc false

  # A module providing a common interface to access and modify a counter used in the DemandCounter implementation.
  # The counter uses :atomics module under the hood.
  # The module allows to create and modify the value of a counter in the same manner both when the counter is about to be accessed
  # from the same node, and from different nodes.

  alias __MODULE__.Worker

  @enforce_keys [:worker, :atomic_ref]
  defstruct @enforce_keys

  @type t :: %__MODULE__{worker: Worker.t(), atomic_ref: :atomics.atomics_ref()}

  defguardp on_the_same_node_as_self(distributed_atomic)
            when distributed_atomic.worker |> node() == self() |> node()

  @spec new(integer() | nil) :: t
  def new(initial_value \\ nil) do
    atomic_ref = :atomics.new(1, [])
    {:ok, worker} = Worker.start_link()

    distributed_atomic = %__MODULE__{
      atomic_ref: atomic_ref,
      worker: worker
    }

    if initial_value != nil do
      :ok = put(distributed_atomic, initial_value)
    end

    distributed_atomic
  end

  @spec add_get(t, integer()) :: integer()
  def add_get(%__MODULE__{} = distributed_atomic, value)
      when on_the_same_node_as_self(distributed_atomic) do
    :atomics.add_get(distributed_atomic.atomic_ref, 1, value)
  end

  def add_get(%__MODULE__{} = distributed_atomic, value) do
    GenServer.call(distributed_atomic.worker, {:add_get, distributed_atomic.atomic_ref, value})
  end

  @spec sub_get(t, integer()) :: integer()
  def sub_get(%__MODULE__{} = distributed_atomic, value)
      when on_the_same_node_as_self(distributed_atomic) do
    :atomics.sub_get(distributed_atomic.atomic_ref, 1, value)
  end

  def sub_get(%__MODULE__{} = distributed_atomic, value) do
    GenServer.cast(distributed_atomic.worker, {:sub_get, distributed_atomic.atomic_ref, value})
  end

  @spec put(t, integer()) :: :ok
  def put(%__MODULE__{} = distributed_atomic, value)
      when on_the_same_node_as_self(distributed_atomic) do
    :atomics.put(distributed_atomic.atomic_ref, 1, value)
  end

  def put(%__MODULE__{} = distributed_atomic, value) do
    GenServer.cast(distributed_atomic.worker, {:put, distributed_atomic.atomic_ref, value})
  end

  @spec get(t) :: integer()
  def get(%__MODULE__{} = distributed_atomic)
      when on_the_same_node_as_self(distributed_atomic) do
    :atomics.get(distributed_atomic.atomic_ref, 1)
  end

  def get(%__MODULE__{} = distributed_atomic) do
    GenServer.call(distributed_atomic.worker, {:get, distributed_atomic.atomic_ref})
  end
end
