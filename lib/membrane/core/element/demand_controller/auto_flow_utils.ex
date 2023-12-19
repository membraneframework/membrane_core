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
    state = Map.update!(state, :awaiting_auto_input_pads, &MapSet.put(&1, pad_ref))
    store_in_queue(pad_ref, :buffers, buffers, state)
  end

  @spec store_event_in_queue(Pad.ref(), Event.t(), State.t()) :: State.t()
  def store_event_in_queue(pad_ref, event, state) do
    store_in_queue(pad_ref, :event, event, state)
  end

  @spec store_stream_format_in_queue(Pad.ref(), StreamFormat.t(), State.t()) :: State.t()
  def store_stream_format_in_queue(pad_ref, stream_format, state) do
    store_in_queue(pad_ref, :stream_format, stream_format, state)
  end

  defp store_in_queue(pad_ref, type, item, state) do
    PadModel.update_data!(state, pad_ref, :auto_flow_queue, &Qex.push(&1, {type, item}))
  end

  @spec auto_adjust_atomic_demand(Pad.ref() | [Pad.ref()], State.t()) :: State.t()
  def auto_adjust_atomic_demand(ref_or_ref_list, state)
      when Pad.is_pad_ref(ref_or_ref_list) or is_list(ref_or_ref_list) do
    ref_or_ref_list
    |> Bunch.listify()
    |> Enum.reduce(state, fn pad_ref, state ->
      PadModel.get_data!(state, pad_ref)
      |> do_auto_adjust_atomic_demand(state)
      |> elem(1)  # todo: usun to :increased / :unchanged, ktore discardujesz w tym elem(1)
    end)
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

      state = PadModel.set_data!(state, ref, :demand, auto_demand_size)
      {:increased, state}
    else
      {:unchanged, state}
    end
  end

  defp do_auto_adjust_atomic_demand(%{ref: ref}, _state) do
    raise "#{__MODULE__}.auto_adjust_atomic_demand/2 can be called only for auto input pads, while #{inspect(ref)} is not such a pad."
  end

  defp increase_atomic_demand?(pad_data, state) do
    state.effective_flow_control == :pull and
      not pad_data.auto_demand_paused? and
      pad_data.demand < pad_data.auto_demand_size / 2 and
      output_auto_demand_positive?(state)
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

    PadModel.get_data!(state, pad_ref, :auto_flow_queue)
    |> Qex.pop()
    |> case do
      {{:value, {:buffers, buffers}}, popped_queue} ->
        state = PadModel.set_data!(state, pad_ref, :auto_flow_queue, popped_queue)
        state = BufferController.exec_buffer_callback(pad_ref, buffers, state)
        pop_stream_formats_and_events(pad_ref, state)

      {:empty, _empty_queue} ->
        Map.update!(state, :awaiting_auto_input_pads, &MapSet.delete(&1, pad_ref))
    end
  end

  defp pop_stream_formats_and_events(pad_ref, state) do
    PadModel.get_data!(state, pad_ref, :auto_flow_queue)
    |> Qex.pop()
    |> case do
      {{:value, {type, item}}, popped_queue} when type in [:event, :stream_format] ->
        state = PadModel.set_data!(state, pad_ref, :auto_flow_queue, popped_queue)
        state = exec_queue_item_callback(pad_ref, {type, item}, state)
        pop_stream_formats_and_events(pad_ref, state)

      {{:value, {:buffers, _buffers}}, _popped_queue} ->
        state

      {:empty, _empty_queue} ->
        Map.update!(state, :awaiting_auto_input_pads, &MapSet.delete(&1, pad_ref))
    end
  end

  defp output_auto_demand_positive?(%State{satisfied_auto_output_pads: pads}),
    do: MapSet.size(pads) == 0

  defp exec_queue_item_callback(pad_ref, {:buffers, buffers}, state) do
    BufferController.exec_buffer_callback(pad_ref, buffers, state)
  end

  defp exec_queue_item_callback(pad_ref, {:event, event}, state) do
    EventController.exec_handle_event(pad_ref, event, state)
  end

  defp exec_queue_item_callback(pad_ref, {:stream_format, stream_format}, state) do
    StreamFormatController.exec_handle_stream_format(pad_ref, stream_format, state)
  end
end
