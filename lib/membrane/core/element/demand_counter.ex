defmodule Membrane.Core.Element.DemandCounter do
  @moduledoc false
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
    def handle_call({:sub_get, atomic_ref, value}, _from, _state) do
      result = :atomics.sub_get(atomic_ref, 1, value)
      {:sub_get, result, nil}
    end

    @impl true
    def handle_call({:get, atomic_ref}, _from, _state) do
      result = :atomics.get(atomic_ref, 1)
      {:sub_get, result, nil}
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

    @type t :: {pid(), :atomics.atomics_ref()}

    @spec new(integer() | nil) :: t
    def new(initial_value \\ nil) do
      atomic_ref = :atomics.new(1, [])
      {:ok, pid} = GenServer.start(Worker, self())
      if initial_value, do: put({pid, atomic_ref}, initial_value)

      {pid, atomic_ref}
    end

    @spec add_get(t, integer()) :: integer()
    def add_get({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.add_get(atomic_ref, 1, value)
    end

    def add_get({pid, atomic_ref}, value) do
      GenServer.call(pid, {:add_get, atomic_ref, value})
    end

    @spec sub_get(t, integer()) :: integer()
    def sub_get({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.sub_get(atomic_ref, 1, value)
    end

    def sub_get({pid, atomic_ref}, value) do
      GenServer.cast(pid, {:sub_get, atomic_ref, value})
    end

    @spec put(t, integer()) :: :ok
    def put({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.put(atomic_ref, 1, value)
    end

    def put({pid, atomic_ref}, value) do
      GenServer.cast(pid, {:put, atomic_ref, value})
    end

    @spec get(t) :: integer()
    def get({pid, atomic_ref}) when node(pid) == node(self()) do
      :atomics.get(atomic_ref, 1)
    end

    def get({pid, atomic_ref}) do
      GenServer.call(pid, {:get, atomic_ref})
    end
  end

  defmodule DistributedEffectiveFlowControl do
    @moduledoc false

    @type t :: DistributedAtomic.t()

    @spec new(EffectiveFlowController.effective_flow_control()) :: t
    def new(initial_value) do
      initial_value
      |> effective_flow_control_to_int()
      |> DistributedAtomic.new()
    end

    @spec get(t) :: EffectiveFlowController.effective_flow_control()
    def get(distributed_atomic) do
      distributed_atomic
      |> DistributedAtomic.get()
      |> int_to_effective_flow_control()
    end

    @spec put(t, EffectiveFlowController.effective_flow_control()) :: :ok
    def put(distributed_atomic, value) do
      value = effective_flow_control_to_int(value)
      DistributedAtomic.put(distributed_atomic, value)
    end

    defp int_to_effective_flow_control(0), do: :not_resolved
    defp int_to_effective_flow_control(1), do: :push
    defp int_to_effective_flow_control(2), do: :pull

    defp effective_flow_control_to_int(:not_resolved), do: 0
    defp effective_flow_control_to_int(:push), do: 1
    defp effective_flow_control_to_int(:pull), do: 2
  end

  @default_overflow_limit_factor -200
  @default_buffered_decrementation_limit 1
  # @default_capacity_factor 200

  @type t :: %__MODULE__{
          counter: DistributedAtomic.t(),
          receiver_mode: DistributedEffectiveFlowControl.t(),
          receiver_process: Process.dest(),
          overflow_limit: neg_integer(),
          buffered_decrementation: non_neg_integer(),
          buffered_decrementation_limit: pos_integer()
        }

  @enforce_keys [
    :counter,
    :receiver_mode,
    :receiver_process
  ]

  defstruct @enforce_keys ++
              [
                overflow_limit: -300,
                buffered_decrementation: 0,
                buffered_decrementation_limit: 1
              ]

  @spec new(
          receiver_mode :: EffectiveFlowController.effective_flow_control(),
          receiver_process :: Process.dest(),
          receiver_demand_unit :: Membrane.Buffer.Metric.unit(),
          overflow_limit :: neg_integer() | nil,
          buffered_decrementation_limit :: pos_integer()
        ) :: t
  def new(
        receiver_mode,
        receiver_process,
        receiver_demand_unit,
        overflow_limit \\ nil,
        buffered_decrementation_limit \\ @default_buffered_decrementation_limit
      ) do
    %__MODULE__{
      counter: DistributedAtomic.new(),
      receiver_mode: DistributedEffectiveFlowControl.new(receiver_mode),
      receiver_process: receiver_process,
      overflow_limit: overflow_limit || default_overflow_limit(receiver_demand_unit),
      buffered_decrementation_limit: buffered_decrementation_limit
    }
  end

  @spec set_receiver_mode(t, EffectiveFlowController.effective_flow_control()) :: :ok
  def set_receiver_mode(%__MODULE__{} = demand_counter, mode) do
    DistributedEffectiveFlowControl.put(
      demand_counter.receiver_mode,
      mode
    )
  end

  @spec get_receiver_mode(t) :: EffectiveFlowController.effective_flow_control()
  def get_receiver_mode(%__MODULE__{} = demand_counter) do
    DistributedEffectiveFlowControl.get(demand_counter.receiver_mode)
  end

  @spec increase(t, non_neg_integer()) :: integer()
  def increase(%__MODULE__{} = demand_counter, value) do
    DistributedAtomic.add_get(demand_counter.counter, value)
  end

  @spec decrease(t, non_neg_integer()) :: {:ok | :overflow, t}
  def decrease(%__MODULE__{} = demand_counter, value) do
    demand_counter = %{
      demand_counter
      | buffered_decrementation: demand_counter.buffered_decrementation + value
    }

    if demand_counter.buffered_decrementation >= demand_counter.buffered_decrementation_limit do
      flush_buffered_decrementation(demand_counter)
    else
      {:ok, demand_counter}
    end
  end

  defp flush_buffered_decrementation(demand_counter) do
    counter_value =
      DistributedAtomic.sub_get(
        demand_counter.counter,
        demand_counter.buffered_decrementation
      )

    demand_counter = %{demand_counter | buffered_decrementation: 0}

    if get_receiver_mode(demand_counter) == :pull and
         counter_value < demand_counter.overflow_limit do
      overflow(counter_value, demand_counter)
      {:overflow, demand_counter}
    else
      {:ok, demand_counter}
    end
  end

  defp overflow(counter_value, demand_counter) do
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

    _result = Process.exit(demand_counter.receiver_process, :kill)
    :ok
  end

  defp default_overflow_limit(demand_unit) do
    Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
      @default_overflow_limit_factor
  end
end
