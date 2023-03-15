defmodule Membrane.Core.Element.Toilet do
  @moduledoc false

  # Toilet is an entity that can be filled and drained. If it's not drained on
  # time and exceeds its capacity, it overflows by logging an error and killing
  # the responsible process (passed on the toilet creation).

  alias Membrane.Core.Element.EffectiveFlowController

  require Membrane.Logger

  defmodule Worker do
    @moduledoc false

    # This is a GenServer created when the counter is about to be accessed from different nodes - it's running on the same node,
    # where the :atomics variable is put, and processes from different nodes can ask it to modify the counter on their behalf.

    use GenServer

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
    def handle_call({:get, atomic_ref}, _from, _state) do
      result = :atomics.get(atomic_ref, 1)
      {:reply, result, nil}
    end

    @impl true
    def handle_cast({:sub, atomic_ref, value}, _state) do
      :atomics.sub(atomic_ref, 1, value)
      {:noreply, nil}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
      {:stop, :normal, state}
    end
  end

  defmodule DistributedCounter do
    @moduledoc false

    # A module providing a common interface to access and modify a counter used in the toilet implementation.
    # The counter uses :atomics module under the hood.
    # The module allows to create and modify the value of a counter in the same manner both when the counter is about to be accessed
    # from the same node, and from different nodes.

    @type t :: {pid(), :atomics.atomics_ref()}

    @spec new() :: t
    def new() do
      atomic_ref = :atomics.new(1, [])
      {:ok, pid} = GenServer.start(Worker, self())
      {pid, atomic_ref}
    end

    @spec add_get(t, integer()) :: integer()
    def add_get({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.add_get(atomic_ref, 1, value)
    end

    def add_get({pid, atomic_ref}, value) do
      GenServer.call(pid, {:add_get, atomic_ref, value})
    end

    @spec sub(t, integer()) :: :ok
    def sub({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.sub(atomic_ref, 1, value)
    end

    def sub({pid, atomic_ref}, value) do
      GenServer.cast(pid, {:sub, atomic_ref, value})
    end
  end

  defmodule DistributedEffectiveFlowControl do
    @moduledoc false

    @type t :: {pid(), :atomics.atomics_ref()}

    @spec new(EffectiveFlowController.effective_flow_control()) :: t
    def new(initial_value) do
      atomic_ref = :atomics.new(1, [])

      initial_value = effective_flow_control_to_int(initial_value)
      :atomics.put(atomic_ref, 1, initial_value)

      {:ok, pid} = GenServer.start(Worker, self())
      {pid, atomic_ref}
    end

    @spec get(t) :: EffectiveFlowController.effective_flow_control()
    def get({pid, atomic_ref}) when node(pid) == node(self()) do
      :atomics.get(atomic_ref, 1)
      |> int_to_effective_flow_control()
    end

    def get({pid, atomic_ref}) do
      GenServer.call(pid, {:get, atomic_ref})
      |> int_to_effective_flow_control()
    end

    # contains implementation only for caller being on this same node, as :atomics,
    # because toilet is created on the receiver side of link and only receiver should
    # call this function
    @spec put(t, EffectiveFlowController.effective_flow_control()) :: :ok
    def put({_pid, atomic_ref}, value) do
      value = effective_flow_control_to_int(value)
      :atomics.put(atomic_ref, 1, value)
    end

    defp int_to_effective_flow_control(0), do: :push
    defp int_to_effective_flow_control(1), do: :pull

    defp effective_flow_control_to_int(:push), do: 0
    defp effective_flow_control_to_int(:pull), do: 1
  end

  @type t :: %__MODULE__{
          counter: DistributedCounter.t(),
          capacity: pos_integer(),
          responsible_process: Process.dest(),
          throttling_factor: pos_integer(),
          unrinsed_buffers_size: non_neg_integer(),
          receiver_effective_flow_control: DistributedEffectiveFlowControl.t(),
          sender_effective_flow_control: DistributedEffectiveFlowControl.t()
        }

  @enforce_keys [
    :counter,
    :capacity,
    :responsible_process,
    :throttling_factor,
    :receiver_effective_flow_control,
    :sender_effective_flow_control
  ]

  defstruct @enforce_keys ++ [unrinsed_buffers_size: 0]

  @default_capacity_factor 200

  @spec new(
          capacity :: pos_integer() | nil,
          demand_unit :: Membrane.Buffer.Metric.unit(),
          responsible_process :: Process.dest(),
          throttling_factor :: pos_integer(),
          receiver_effective_flow_control :: EffectiveFlowController.effective_flow_control(),
          sender_effective_flow_control :: EffectiveFlowController.effective_flow_control()
        ) :: t
  def new(
        capacity,
        demand_unit,
        responsible_process,
        throttling_factor,
        sender_effective_flow_control,
        receiver_effective_flow_control
      ) do
    default_capacity =
      Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
        @default_capacity_factor

    capacity = capacity || default_capacity

    receiver_effective_flow_control =
      receiver_effective_flow_control
      |> DistributedEffectiveFlowControl.new()

    sender_effective_flow_control =
      sender_effective_flow_control
      |> DistributedEffectiveFlowControl.new()

    %__MODULE__{
      counter: DistributedCounter.new(),
      capacity: capacity,
      responsible_process: responsible_process,
      throttling_factor: throttling_factor,
      receiver_effective_flow_control: receiver_effective_flow_control,
      sender_effective_flow_control: sender_effective_flow_control
    }
  end

  @spec set_receiver_effective_flow_control(t, EffectiveFlowController.effective_flow_control()) ::
          :ok
  def set_receiver_effective_flow_control(%__MODULE__{} = toilet, value) do
    DistributedEffectiveFlowControl.put(
      toilet.receiver_effective_flow_control,
      value
    )
  end

  @spec set_sender_effective_flow_control(t, EffectiveFlowController.effective_flow_control()) ::
          :ok
  def set_sender_effective_flow_control(%__MODULE__{} = toilet, value) do
    DistributedEffectiveFlowControl.put(
      toilet.sender_effective_flow_control,
      value
    )
  end

  @spec fill(t, non_neg_integer) :: {:ok | :overflow, t}
  def fill(%__MODULE__{} = toilet, amount) do
    new_unrinsed_buffers_size = toilet.unrinsed_buffers_size + amount

    if new_unrinsed_buffers_size < toilet.throttling_factor do
      {:ok, %{toilet | unrinsed_buffers_size: new_unrinsed_buffers_size}}
    else
      size = DistributedCounter.add_get(toilet.counter, new_unrinsed_buffers_size)

      %{toilet | unrinsed_buffers_size: 0}
      |> check_overflow(size)
    end
  end

  @spec check_overflow(t, integer) :: {:ok | :overflow, t}
  defp check_overflow(%__MODULE__{} = toilet, size) do
    endpoints_effective_flow_control(toilet)
    |> case do
      %{sender: :push, receiver: :pull} when size > toilet.capacity ->
        overflow(size, toilet.capacity, toilet.responsible_process)
        {:overflow, toilet}

      %{} ->
        {:ok, toilet}
    end
  end

  @spec endpoints_effective_flow_control(t) :: map()
  defp endpoints_effective_flow_control(%__MODULE__{} = toilet) do
    %{
      sender:
        toilet.sender_effective_flow_control
        |> DistributedEffectiveFlowControl.get(),
      receiver:
        toilet.receiver_effective_flow_control
        |> DistributedEffectiveFlowControl.get()
    }
  end

  @spec drain(t, non_neg_integer) :: :ok
  def drain(%__MODULE__{} = toilet, amount) do
    DistributedCounter.sub(toilet.counter, amount)
  end

  defp overflow(size, capacity, responsible_process) do
    Membrane.Logger.debug_verbose(~S"""
    Toilet overflow

                 ` ' `
             .'''. ' .'''.
               .. ' ' ..
              '  '.'.'  '
              .'''.'.'''.
             ' .''.'.''. '
           ;------ ' ------;
           | ~~ .--'--//   |
           |   /   '   \   |
           |  /    '    \  |
           |  |    '    |  |  ,----.
           |   \ , ' , /   | =|____|=
           '---,###'###,---'  (---(
              /##  '  ##\      )---)
              |##, ' ,##|     (---(
               \'#####'/       `---`
                \`"#"`/
                 |`"`|
               .-|   |-.
              /  '   '  \
              '---------'
    """)

    Membrane.Logger.error("""
    Toilet overflow.

    Reached the size of #{inspect(size)}, which is above toilet capacity (#{inspect(capacity)})
    when storing data from output working in push mode. It means that some element in the pipeline
    processes the stream too slow or doesn't process it at all.
    To have control over amount of buffers being produced, consider using output in :auto or :manual
    flow control mode. (see `Membrane.Pad.flow_control`).
    You can also try changing the `toilet_capacity` in `Membrane.ChildrenSpec.via_in/3`.
    """)

    Process.exit(responsible_process, :kill)
  end
end
