defmodule Membrane.Core.Element.DemandController.AutoFlowUtils do
  @moduledoc false

  alias Membrane.Buffer
  alias Membrane.Event
  alias Membrane.StreamFormat

  alias Membrane.Core.Element.{
    AtomicDemand,
    BufferController,
    EventController,
    State,
    StreamFormatController
  }

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @empty_map_set MapSet.new()

  # Description of the auto flow control queueing mechanism

  # General concept: Buffers coming to auto input pads should be handled only if
  # all auto output pads have positive demand. Buffers arriving when any of the auto
  # output pads has negative demand should be queued and only processed when the
  # demand everywhere is positive

  # Fields in Element state, that take important part in this mechanism:
  #   - satisfied_auto_output_pads - MapSet of auto output pads, whose demand is less than or equal to 0.
  #     We consider only pads with the end_of_stream? flag set to false
  #   - awaiting_auto_input_pads - MapSet of auto input pads, which have a non-empty auto_flow_queue
  #   - popping_auto_flow_queue? - a flag determining whether we are on the stack somewhere above popping a queue.
  #     It's used to avoid situations where the function that pops from the queue calls itself multiple times,
  #     what could potentially lead to things like altering the order of sent buffers.

  # Each auto input pad in PadData contains a queue in the :auto_flow_queue field, in which it stores queued
  # buffers, events and stream formats. If queue is non-empty, corresponding pad_ref should be
  # in the Mapset awaiting_auto_input_pads in element state

  # The introduced mechanism consists of two parts, the pseudocode for which is included below

  # def onBufferArrived() do
  #   if element uncorked do
  #     exec handle_buffer
  #   else
  #     store buffer in queue
  #   end
  # end

  # def onUncorck() do
  #   # EFC means `effective flow control`

  #   if EFC == pull do
  #     bump demand on auto input pads with an empty queue
  #   end

  #   while (output demand positive or EFC == push) and some queues are not empty do
  #     pop random queue and handle its head
  #   end

  #   if EFC == pull do
  #     bump demand on auto input pads with an empty queue
  #   end
  # end

  # An Element is `corked` when its effective flow control is :pull and it has an auto output pad,
  # who's demand is non-positive

  # The following events can make the element shift from `corked` state to `uncorked` state:
  #   - change of effective flow control from :pull to :push
  #   - increase in the value of auto output pad demand. We check the demand value:
  #     - after sending the buffer to a given output pad
  #     - after receiving a message :atomic_demand_increased from the next element
  #   - unlinking the auto output pad
  #   - sending an EOS to the auto output pad

  # In addition, an invariant is maintained, which is that the head of all non-empty
  # auto_flow_queue queues contains a buffer (the queue can also contain events and
  # stream formats). After popping a queue
  # of a given pad, if it has an event or stream format in its head, we pop it further,
  # until it becomes empty or a buffer is encountered.

  # auto_flow_queues hold single buffers, event if they arrive to the element in batch, because if we
  # done otherwise, we would have to handle whole batch after popping it from the queue, even if demand
  # of all output pads would be satisfied after handling first buffer

  defguardp is_input_auto_pad_data(pad_data)
            when is_map(pad_data) and is_map_key(pad_data, :flow_control) and
                   pad_data.flow_control == :auto and is_map_key(pad_data, :direction) and
                   pad_data.direction == :input

  @spec pause_demands(Pad.ref(), State.t()) :: State.t()
  def pause_demands(pad_ref, state) do
    :ok = ensure_auto_input_pad!(pad_ref, :pause_auto_demand, state)
    set_auto_demand_paused_flag(pad_ref, true, state)
  end

  @spec resume_demands(Pad.ref(), State.t()) :: State.t()
  def resume_demands(pad_ref, state) do
    :ok = ensure_auto_input_pad!(pad_ref, :resume_auto_demand, state)
    state = set_auto_demand_paused_flag(pad_ref, false, state)
    auto_adjust_atomic_demand(pad_ref, state)
  end

  defp ensure_auto_input_pad!(pad_ref, action, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{direction: :input, flow_control: :auto} ->
        :ok

      %{direction: :output} ->
        raise Membrane.ElementError,
              "Action #{inspect(action)} can only be returned for input pads, but #{inspect(pad_ref)} is an output pad"

      %{flow_control: flow_control} ->
        raise Membrane.ElementError,
              "Action #{inspect(action)} can only be returned for pads with :auto flow control, but #{inspect(pad_ref)} pad flow control is #{inspect(flow_control)}"
    end
  end

  @spec set_auto_demand_paused_flag(Pad.ref(), boolean(), State.t()) :: State.t()
  defp set_auto_demand_paused_flag(pad_ref, paused?, state) do
    {old_value, state} =
      PadModel.get_and_update_data!(state, pad_ref, :auto_demand_paused?, &{&1, paused?})

    if old_value == paused? do
      operation = if paused?, do: "pause", else: "resume"

      Membrane.Logger.debug_verbose(
        "Tried to #{operation} auto demand on pad #{inspect(pad_ref)}, while it has been already #{operation}d"
      )
    end

    state
  end

  @spec store_buffers_in_queue(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def store_buffers_in_queue(pad_ref, buffers, state) do
    state
    |> Map.update!(:awaiting_auto_input_pads, &MapSet.put(&1, pad_ref))
    |> PadModel.update_data!(pad_ref, :auto_flow_queue, fn queue ->
      Enum.reduce(buffers, queue, fn buffer, queue ->
        Qex.push(queue, {:buffer, buffer})
      end)
    end)
  end

  @spec store_event_in_queue(Pad.ref(), Event.t(), State.t()) :: State.t()
  def store_event_in_queue(pad_ref, event, state) do
    queue_item = {:event, event}
    PadModel.update_data!(state, pad_ref, :auto_flow_queue, &Qex.push(&1, queue_item))
  end

  @spec store_stream_format_in_queue(Pad.ref(), StreamFormat.t(), State.t()) :: State.t()
  def store_stream_format_in_queue(pad_ref, stream_format, state) do
    queue_item = {:stream_format, stream_format}
    PadModel.update_data!(state, pad_ref, :auto_flow_queue, &Qex.push(&1, queue_item))
  end

  @spec auto_adjust_atomic_demand(Pad.ref() | [Pad.ref()], State.t()) :: State.t()
  def auto_adjust_atomic_demand(pad_ref_list, state) when is_list(pad_ref_list) do
    pad_ref_list
    |> Enum.reduce(state, fn pad_ref, state ->
      PadModel.get_data!(state, pad_ref)
      |> do_auto_adjust_atomic_demand(state)
    end)
  end

  def auto_adjust_atomic_demand(pad_ref, state) do
    PadModel.get_data!(state, pad_ref)
    |> do_auto_adjust_atomic_demand(state)
  end

  defp do_auto_adjust_atomic_demand(pad_data, state) when is_input_auto_pad_data(pad_data) do
    if increase_atomic_demand?(pad_data, state) do
      %{
        ref: ref,
        auto_demand_size: auto_demand_size,
        demand: demand,
        atomic_demand: atomic_demand,
        stalker_metrics: stalker_metrics
      } = pad_data

      diff = auto_demand_size - demand
      :ok = AtomicDemand.increase(atomic_demand, diff)

      :atomics.put(stalker_metrics.demand, 1, auto_demand_size)

      PadModel.set_data!(state, ref, :demand, auto_demand_size)
    else
      state
    end
  end

  defp do_auto_adjust_atomic_demand(%{ref: ref}, _state) do
    raise "#{__MODULE__}.auto_adjust_atomic_demand/2 can be called only for auto input pads, while #{inspect(ref)} is not such a pad."
  end

  defp increase_atomic_demand?(pad_data, state) do
    state.effective_flow_control == :pull and
      not pad_data.auto_demand_paused? and
      pad_data.demand < pad_data.auto_demand_size / 2 and
      state.satisfied_auto_output_pads == @empty_map_set
  end

  @spec pop_queues_and_bump_demand(State.t()) :: State.t()
  def pop_queues_and_bump_demand(%State{popping_auto_flow_queue?: true} = state), do: state

  def pop_queues_and_bump_demand(%State{} = state) do
    %{state | popping_auto_flow_queue?: true}
    |> pop_auto_flow_queues_while_needed()
    |> bump_demand()
    |> Map.put(:popping_auto_flow_queue?, false)
  end

  defp bump_demand(state) do
    if state.effective_flow_control == :pull and
         state.satisfied_auto_output_pads == @empty_map_set do
      do_bump_demand(state)
    else
      state
    end
  end

  defp do_bump_demand(state) do
    state.auto_input_pads
    |> Enum.reject(&MapSet.member?(state.awaiting_auto_input_pads, &1))
    |> Enum.reduce(state, fn pad_ref, state ->
      pad_data = PadModel.get_data!(state, pad_ref)

      if not pad_data.auto_demand_paused? and
           pad_data.demand < pad_data.auto_demand_size / 2 do
        diff = pad_data.auto_demand_size - pad_data.demand
        :ok = AtomicDemand.increase(pad_data.atomic_demand, diff)

        :atomics.put(pad_data.stalker_metrics.demand, 1, pad_data.auto_demand_size)

        PadModel.set_data!(state, pad_ref, :demand, pad_data.auto_demand_size)
      else
        state
      end
    end)
  end

  @spec pop_auto_flow_queues_while_needed(State.t()) :: State.t()
  def pop_auto_flow_queues_while_needed(state) do
    if (state.effective_flow_control == :push or
          MapSet.size(state.satisfied_auto_output_pads) == 0) and
         MapSet.size(state.awaiting_auto_input_pads) > 0 do
      pop_random_auto_flow_queue(state)
      |> pop_auto_flow_queues_while_needed()
    else
      state
    end
  end

  defp pop_random_auto_flow_queue(state) do
    pad_ref = Enum.random(state.awaiting_auto_input_pads)

    state
    |> PadModel.get_data!(pad_ref, :auto_flow_queue)
    |> Qex.pop()
    |> case do
      {{:value, {:buffer, buffer}}, popped_queue} ->
        state = PadModel.set_data!(state, pad_ref, :auto_flow_queue, popped_queue)
        state = BufferController.exec_buffer_callback(pad_ref, [buffer], state)
        pop_stream_formats_and_events(pad_ref, state)

      {:empty, _empty_queue} ->
        Map.update!(state, :awaiting_auto_input_pads, &MapSet.delete(&1, pad_ref))
    end
  end

  defp pop_stream_formats_and_events(pad_ref, state) do
    PadModel.get_data!(state, pad_ref, :auto_flow_queue)
    |> Qex.pop()
    |> case do
      {{:value, {:event, event}}, popped_queue} ->
        state = PadModel.set_data!(state, pad_ref, :auto_flow_queue, popped_queue)
        state = EventController.exec_handle_event(pad_ref, event, state)
        pop_stream_formats_and_events(pad_ref, state)

      {{:value, {:stream_format, stream_format}}, popped_queue} ->
        state = PadModel.set_data!(state, pad_ref, :auto_flow_queue, popped_queue)
        state = StreamFormatController.exec_handle_stream_format(pad_ref, stream_format, state)
        pop_stream_formats_and_events(pad_ref, state)

      {{:value, {:buffer, _buffer}}, _popped_queue} ->
        state

      {:empty, _empty_queue} ->
        Map.update!(state, :awaiting_auto_input_pads, &MapSet.delete(&1, pad_ref))
    end
  end

  # defp output_auto_demand_positive?(%State{satisfied_auto_output_pads: pads}),
  #   do: MapSet.size(pads) == 0
end
