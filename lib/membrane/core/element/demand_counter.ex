defmodule Membrane.Core.Element.DemandCounter do
  @moduledoc false
  alias Membrane.Core.Element.EffectiveFlowController

  alias __MODULE__.{
    DistributedAtomic,
    DistributedFlowMode
  }

  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @default_overflow_limit_factor -200
  @default_buffered_decrementation_limit 1
  @distributed_buffered_decrementation_limit 150

  @opaque t :: %__MODULE__{
            counter: DistributedAtomic.t(),
            receiver_mode: DistributedFlowMode.t(),
            receiver_process: Process.dest(),
            sender_mode: DistributedFlowMode.t(),
            sender_process: Process.dest(),
            sender_pad_ref: Pad.ref(),
            overflow_limit: neg_integer(),
            buffered_decrementation: non_neg_integer(),
            buffered_decrementation_limit: pos_integer(),
            toilet_overflowed?: boolean()
          }

  @type flow_mode :: DistributedFlowMode.flow_mode_value()

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

    if old_counter_value <= 0 do
      Message.send(
        demand_counter.sender_process,
        :demand_counter_increased,
        demand_counter.sender_pad_ref
      )
    end

    :ok
  end

  @spec decrease(t, non_neg_integer()) :: t
  def decrease(%__MODULE__{} = demand_counter, value) do
    demand_counter = Map.update!(demand_counter, :buffered_decrementation, &(&1 + value))

    if demand_counter.buffered_decrementation >= demand_counter.buffered_decrementation_limit do
      flush_buffered_decrementation(demand_counter)
    else
      demand_counter
    end
  end

  @spec get(t) :: integer()
  def get(%__MODULE__{} = demand_counter) do
    DistributedAtomic.get(demand_counter.counter)
  end

  defp flush_buffered_decrementation(demand_counter) do
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
