defmodule Membrane.Core.Element.AtomicDemand do
  @moduledoc false

  alias Membrane.Core.Element.EffectiveFlowController

  alias __MODULE__.{
    DistributedAtomic,
    AtomicFlowStatus
  }

  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @default_toilet_capacity_factor 200
  @default_throttling_factor 1
  @distributed_default_throttling_factor 150

  @opaque t :: %__MODULE__{
            counter: DistributedAtomic.t(),
            receiver_status: AtomicFlowStatus.t(),
            receiver_process: Process.dest(),
            sender_status: AtomicFlowStatus.t(),
            sender_process: Process.dest(),
            sender_pad_ref: Pad.ref(),
            toilet_capacity: neg_integer(),
            buffered_decrementation: non_neg_integer(),
            throttling_factor: pos_integer(),
            toilet_overflowed?: boolean(),
            receiver_demand_unit: Membrane.Buffer.Metric.unit()
          }

  @type flow_mode :: AtomicFlowStatus.value()

  @enforce_keys [
    :counter,
    :receiver_status,
    :receiver_process,
    :sender_status,
    :sender_process,
    :sender_pad_ref,
    :throttling_factor,
    :toilet_capacity,
    :receiver_demand_unit
  ]

  defstruct @enforce_keys ++ [buffered_decrementation: 0, toilet_overflowed?: false]

  @spec new(%{
          :receiver_effective_flow_control => EffectiveFlowController.effective_flow_control(),
          :receiver_process => Process.dest(),
          :receiver_demand_unit => Membrane.Buffer.Metric.unit(),
          :sender_process => Process.dest(),
          :sender_pad_ref => Pad.ref(),
          :supervisor => pid(),
          optional(:toilet_capacity) => non_neg_integer() | nil,
          optional(:throttling_factor) => pos_integer() | nil
        }) :: t
  def new(
        %{
          receiver_effective_flow_control: receiver_effective_flow_control,
          receiver_process: receiver_process,
          receiver_demand_unit: receiver_demand_unit,
          sender_process: sender_process,
          sender_pad_ref: sender_pad_ref,
          supervisor: supervisor
        } = options
      ) do
    toilet_capacity = options[:toilet_capacity]
    throttling_factor = options[:throttling_factor]

    counter = DistributedAtomic.new(supervisor: supervisor)

    throttling_factor =
      cond do
        throttling_factor != nil -> throttling_factor
        node(sender_process) == node(counter.worker) -> @default_throttling_factor
        true -> @distributed_default_throttling_factor
      end

    receiver_status =
      AtomicFlowStatus.new(
        {:resolved, receiver_effective_flow_control},
        supervisor: supervisor
      )

    %__MODULE__{
      counter: counter,
      receiver_status: receiver_status,
      receiver_process: receiver_process,
      sender_status: AtomicFlowStatus.new(:to_be_resolved, supervisor: supervisor),
      sender_process: sender_process,
      sender_pad_ref: sender_pad_ref,
      toilet_capacity: toilet_capacity || default_toilet_capacity(receiver_demand_unit),
      throttling_factor: throttling_factor,
      receiver_demand_unit: receiver_demand_unit
    }
  end

  @spec set_sender_status(t, AtomicFlowStatus.value()) :: :ok
  def set_sender_status(%__MODULE__{} = atomic_demand, mode) do
    AtomicFlowStatus.set(
      atomic_demand.sender_status,
      mode
    )
  end

  @spec get_sender_status(t) :: AtomicFlowStatus.value()
  def get_sender_status(%__MODULE__{} = atomic_demand) do
    AtomicFlowStatus.get(atomic_demand.sender_status)
  end

  @spec set_receiver_status(t, AtomicFlowStatus.value()) :: :ok
  def set_receiver_status(%__MODULE__{} = atomic_demand, mode) do
    AtomicFlowStatus.set(
      atomic_demand.receiver_status,
      mode
    )
  end

  @spec get_receiver_status(t) :: AtomicFlowStatus.value()
  def get_receiver_status(%__MODULE__{} = atomic_demand) do
    AtomicFlowStatus.get(atomic_demand.receiver_status)
  end

  @spec increase(t, non_neg_integer()) :: :ok
  def increase(%__MODULE__{} = atomic_demand, value) do
    new_atomic_demand_value = DistributedAtomic.add_get(atomic_demand.counter, value)
    old_atomic_demand_value = new_atomic_demand_value - value

    if old_atomic_demand_value <= 0 do
      Message.send(
        atomic_demand.sender_process,
        :atomic_demand_increased,
        atomic_demand.sender_pad_ref
      )
    end

    :ok
  end

  @spec decrease(t, non_neg_integer()) :: {{:decreased, integer()}, t} | {:unchanged, t}
  def decrease(%__MODULE__{} = atomic_demand, value) do
    atomic_demand = Map.update!(atomic_demand, :buffered_decrementation, &(&1 + value))

    if atomic_demand.buffered_decrementation >= atomic_demand.throttling_factor do
      flush_buffered_decrementation(atomic_demand)
    else
      {:unchanged, atomic_demand}
    end
  end

  @spec get(t) :: integer()
  def get(%__MODULE__{} = atomic_demand) do
    DistributedAtomic.get(atomic_demand.counter)
  end

  defp flush_buffered_decrementation(atomic_demand) do
    atomic_demand_value =
      DistributedAtomic.sub_get(
        atomic_demand.counter,
        atomic_demand.buffered_decrementation
      )

    atomic_demand = %{atomic_demand | buffered_decrementation: 0}

    atomic_demand =
      if not atomic_demand.toilet_overflowed? and
           get_receiver_status(atomic_demand) == {:resolved, :pull} and
           get_sender_status(atomic_demand) == {:resolved, :push} and
           -1 * atomic_demand_value > atomic_demand.toilet_capacity do
        overflow(atomic_demand, atomic_demand_value)
      else
        atomic_demand
      end

    {{:decreased, atomic_demand_value}, atomic_demand}
  end

  defp overflow(atomic_demand, atomic_demand_value) do
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

    Atomic demand reached the size of #{inspect(atomic_demand_value)}, which means that there are #{inspect(-1 * atomic_demand_value)}
    #{atomic_demand.receiver_demand_unit} sent without demanding it, which is above toilet capacity (#{inspect(atomic_demand.toilet_capacity)})
    when storing data from output working in push mode. It means that some element in the pipeline
    processes the stream too slow or doesn't process it at all.
    To have control over amount of buffers being produced, consider using output in :auto or :manual
    flow control mode. (see `Membrane.Pad.flow_control`).
    You can also try changing the `toilet_capacity` in `Membrane.ChildrenSpec.via_in/3`.
    """)

    Process.exit(atomic_demand.receiver_process, :kill)

    %{atomic_demand | toilet_overflowed?: true}
  end

  defp default_toilet_capacity(demand_unit) do
    Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
      @default_toilet_capacity_factor
  end
end
