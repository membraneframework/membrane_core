defmodule Membrane.Core.Element.DemandCounter do
  @moduledoc false
  alias Membrane.Core.Element.EffectiveFlowController

  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  defmodule Worker do
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

  defmodule DistributedAtomic do
    @moduledoc false

    # A module providing a common interface to access and modify a counter used in the toilet implementation.
    # The counter uses :atomics module under the hood.
    # The module allows to create and modify the value of a counter in the same manner both when the counter is about to be accessed
    # from the same node, and from different nodes.

    @enforce_keys [:worker, :atomic_ref]
    defstruct @enforce_keys

    @type t :: %__MODULE__{worker: Worker.t(), atomic_ref: :atomics.atomics_ref()}

    defguardp on_this_same_node_as_self(distributed_atomic)
              when distributed_atomic.worker |> node() == self() |> node()

    @spec new(integer() | nil) :: t
    def new(initial_value \\ nil) do
      atomic_ref = :atomics.new(1, [])
      {:ok, worker} = Worker.start(self())

      distributed_atomic = %__MODULE__{
        atomic_ref: atomic_ref,
        worker: worker
      }

      if initial_value, do: put(distributed_atomic, initial_value)

      distributed_atomic
    end

    @spec add_get(t, integer()) :: integer()
    def add_get(%__MODULE__{} = distributed_atomic, value)
        when on_this_same_node_as_self(distributed_atomic) do
      :atomics.add_get(distributed_atomic.atomic_ref, 1, value)
    end

    def add_get(%__MODULE__{} = distributed_atomic, value) do
      GenServer.call(distributed_atomic.worker, {:add_get, distributed_atomic.atomic_ref, value})
    end

    @spec sub_get(t, integer()) :: integer()
    def sub_get(%__MODULE__{} = distributed_atomic, value)
        when on_this_same_node_as_self(distributed_atomic) do
      :atomics.sub_get(distributed_atomic.atomic_ref, 1, value)
    end

    def sub_get(%__MODULE__{} = distributed_atomic, value) do
      GenServer.cast(distributed_atomic.worker, {:sub_get, distributed_atomic.atomic_ref, value})
    end

    @spec put(t, integer()) :: :ok
    def put(%__MODULE__{} = distributed_atomic, value)
        when on_this_same_node_as_self(distributed_atomic) do
      :atomics.put(distributed_atomic.atomic_ref, 1, value)
    end

    def put(%__MODULE__{} = distributed_atomic, value) do
      GenServer.cast(distributed_atomic.worker, {:put, distributed_atomic.atomic_ref, value})
    end

    @spec get(t) :: integer()
    def get(%__MODULE__{} = distributed_atomic)
        when on_this_same_node_as_self(distributed_atomic) do
      :atomics.get(distributed_atomic.atomic_ref, 1)
    end

    def get(%__MODULE__{} = distributed_atomic) do
      GenServer.call(distributed_atomic.worker, {:get, distributed_atomic.atomic_ref})
    end
  end

  defmodule DistributedFlowMode do
    @moduledoc false

    @type t :: DistributedAtomic.t()
    @type flow_mode_value ::
            EffectiveFlowController.effective_flow_control() | :to_be_resolved

    @spec new(flow_mode_value) :: t
    def new(initial_value) do
      initial_value
      |> flow_mode_to_int()
      |> DistributedAtomic.new()
    end

    @spec get(t) :: flow_mode_value()
    def get(distributed_atomic) do
      distributed_atomic
      |> DistributedAtomic.get()
      |> int_to_flow_mode()
    end

    @spec put(t, flow_mode_value()) :: :ok
    def put(distributed_atomic, value) do
      value = flow_mode_to_int(value)
      DistributedAtomic.put(distributed_atomic, value)
    end

    defp int_to_flow_mode(0), do: :to_be_resolved
    defp int_to_flow_mode(1), do: :push
    defp int_to_flow_mode(2), do: :pull

    defp flow_mode_to_int(:to_be_resolved), do: 0
    defp flow_mode_to_int(:push), do: 1
    defp flow_mode_to_int(:pull), do: 2
  end

  @default_overflow_limit_factor -200
  @default_buffered_decrementation_limit 1
  @distributed_buffered_decrementation_limit 150

  @type t :: %__MODULE__{
          counter: DistributedAtomic.t(),
          receiver_mode: DistributedFlowMode.t(),
          receiver_process: Process.dest(),
          overflow_limit: neg_integer(),
          buffered_decrementation: non_neg_integer(),
          buffered_decrementation_limit: pos_integer()
        }

  @type flow_mode :: DistributedFlowMode.flow_mode()

  @enforce_keys [
    :counter,
    :receiver_mode,
    :receiver_process,
    :sender_mode,
    :sender_process,
    :sender_pad_ref,
    :buffered_decrementation_limit,
    :overflow_limit
  ]

  defstruct @enforce_keys ++ [buffered_decrementation: 0, toilet_overflowed?: false]

  @spec new(
          receiver_mode :: EffectiveFlowController.effective_flow_control(),
          receiver_process :: Process.dest(),
          receiver_demand_unit :: Membrane.Buffer.Metric.unit(),
          sender_process :: Process.dest(),
          sender_pad_ref :: Pad.ref(),
          overflow_limit :: neg_integer() | nil
        ) :: t
  def new(
        receiver_mode,
        receiver_process,
        receiver_demand_unit,
        sender_process,
        sender_pad_ref,
        overflow_limit \\ nil
      ) do
    %DistributedAtomic{worker: worker} = counter = DistributedAtomic.new()

    buffered_decrementation_limit =
      if node(sender_process) ==
           node(worker),
         do: @default_buffered_decrementation_limit,
         else: @distributed_buffered_decrementation_limit

    %__MODULE__{
      counter: counter,
      receiver_mode: DistributedFlowMode.new(receiver_mode),
      receiver_process: receiver_process,
      sender_mode: DistributedFlowMode.new(:to_be_resolved),
      sender_process: sender_process,
      sender_pad_ref: sender_pad_ref,
      overflow_limit: overflow_limit || default_overflow_limit(receiver_demand_unit),
      buffered_decrementation_limit: buffered_decrementation_limit
    }
  end

  @spec set_sender_mode(t, EffectiveFlowController.effective_flow_control()) :: :ok
  def set_sender_mode(%__MODULE__{} = demand_counter, mode) do
    DistributedFlowMode.put(
      demand_counter.sender_mode,
      mode
    )
  end

  @spec get_sender_mode(t) :: flow_mode()
  def get_sender_mode(%__MODULE__{} = demand_counter) do
    DistributedFlowMode.get(demand_counter.sender_mode)
  end

  @spec set_receiver_mode(t, flow_mode()) :: :ok
  def set_receiver_mode(%__MODULE__{} = demand_counter, mode) do
    DistributedFlowMode.put(
      demand_counter.receiver_mode,
      mode
    )
  end

  @spec get_receiver_mode(t) :: flow_mode()
  def get_receiver_mode(%__MODULE__{} = demand_counter) do
    DistributedFlowMode.get(demand_counter.receiver_mode)
  end

  @spec increase(t, non_neg_integer()) :: :ok
  def increase(%__MODULE__{} = demand_counter, value) do
    new_counter_value = DistributedAtomic.add_get(demand_counter.counter, value)
    old_counter_value = new_counter_value - value

    Membrane.Logger.warn(
      "DEMAND COUNTER OLD NEW #{inspect({old_counter_value, new_counter_value})}"
    )

    if old_counter_value <= 0 do
      ref = make_ref()

      Membrane.Logger.warn(
        "SENDING DC NOTIFICATION #{inspect(Message.new(:demand_counter_increased, [ref, demand_counter.sender_pad_ref]))}"
      )

      Message.send(
        demand_counter.sender_process,
        :demand_counter_increased,
        [ref, demand_counter.sender_pad_ref]
      )
    end

    :ok
  end

  @spec decrease(t, non_neg_integer()) :: t
  def decrease(%__MODULE__{} = demand_counter, value) do
    demand_counter = %{
      demand_counter
      | buffered_decrementation: demand_counter.buffered_decrementation + value
    }

    xd = get(demand_counter)

    dc =
      if demand_counter.buffered_decrementation >= demand_counter.buffered_decrementation_limit do
        flush_buffered_decrementation(demand_counter)
      else
        demand_counter
      end

    Membrane.Logger.warn("DEMAND COUNTER DECREMENTATION #{inspect(xd)} -> #{inspect(get(dc))}")

    dc
  end

  @spec get(t) :: integer()
  def get(%__MODULE__{} = demand_counter) do
    DistributedAtomic.get(demand_counter.counter)
  end

  @spec flush_buffered_decrementation(t) :: t
  def flush_buffered_decrementation(demand_counter) do
    counter_value =
      DistributedAtomic.sub_get(
        demand_counter.counter,
        demand_counter.buffered_decrementation
      )

    demand_counter = %{demand_counter | buffered_decrementation: 0}

    if not demand_counter.toilet_overflowed? and
         get_receiver_mode(demand_counter) == :pull and
         get_sender_mode(demand_counter) == :push and
         counter_value < demand_counter.overflow_limit do
      overflow(demand_counter, counter_value)
    else
      demand_counter
    end
  end

  defp overflow(demand_counter, counter_value) do
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

    Reached the size of #{inspect(counter_value)}, which is below overflow limit (#{inspect(demand_counter.overflow_limit)})
    when storing data from output working in push mode. It means that some element in the pipeline
    processes the stream too slow or doesn't process it at all.
    To have control over amount of buffers being produced, consider using output in :auto or :manual
    flow control mode. (see `Membrane.Pad.flow_control`).
    You can also try changing the `toilet_capacity` in `Membrane.ChildrenSpec.via_in/3`.
    """)

    Process.exit(demand_counter.receiver_process, :kill)

    %{demand_counter | toilet_overflowed?: true}
  end

  defp default_overflow_limit(demand_unit) do
    Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
      @default_overflow_limit_factor
  end
end
