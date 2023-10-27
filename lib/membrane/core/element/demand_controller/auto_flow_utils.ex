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

  @spec hard_corcked?(Pad.ref(), State.t()) :: boolean()
  def hard_corcked?(pad_ref, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    state.effective_flow_control == :pull and pad_data.direction == :input and
      pad_data.flow_control == :auto and pad_data.demand < 0
  end

  @spec auto_flow_queue_empty?(Pad.ref(), State.t()) :: boolean()
  def auto_flow_queue_empty?(pad_ref, state) do
    PadModel.get_data!(state, pad_ref, :auto_flow_queue) == Qex.new()
  end

  @spec store_buffers_in_queue(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def store_buffers_in_queue(pad_ref, buffers, state) do
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
  def auto_adjust_atomic_demand(pad_ref_list, state) when is_list(pad_ref_list) do
    {bumped_pads, state} =
      pad_ref_list
      |> Enum.flat_map_reduce(state, fn pad_ref, state ->
        PadModel.get_data!(state, pad_ref)
        |> do_auto_adjust_atomic_demand(state)
        |> case do
          {:increased, state} -> {[pad_ref], state}
          {:unchanged, state} -> {[], state}
        end
      end)

    flush_auto_flow_queues(bumped_pads, state)
  end

  def auto_adjust_atomic_demand(pad_ref, state) when Pad.is_pad_ref(pad_ref) do
    PadModel.get_data!(state, pad_ref)
    |> do_auto_adjust_atomic_demand(state)
    |> case do
      {:increased, state} ->
        flush_auto_flow_queues([pad_ref], state)

      {:unchanged, state} ->
        state
    end
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
      Enum.all?(pad_data.associated_pads, &atomic_demand_positive?(&1, state))
  end

  defp atomic_demand_positive?(pad_ref, state) do
    atomic_demand_value =
      PadModel.get_data!(state, pad_ref, :atomic_demand)
      |> AtomicDemand.get()

    atomic_demand_value > 0
  end

  defp flush_auto_flow_queues(pad_ref_list, state) do
    pad_ref_list
    |> Enum.reject(&hard_corcked?(&1, state))
    |> do_flush_auto_flow_queues(state)
  end

  defp do_flush_auto_flow_queues([], state), do: state

  defp do_flush_auto_flow_queues(pads_to_flush, state) do
    selected_pad = Enum.random(pads_to_flush)

    PadModel.get_data!(state, selected_pad, :auto_flow_queue)
    |> Qex.pop()
    |> case do
      {{:value, queue_item}, popped_queue} ->
        state =
          exec_queue_item_callback(selected_pad, queue_item, state)
          |> PadModel.set_data!(selected_pad, :auto_flow_queue, popped_queue)

          do_flush_auto_flow_queues(pads_to_flush, state)

      {:empty, empty_queue} ->
        state = PadModel.set_data!(state, selected_pad, :auto_flow_queue, empty_queue)

        pads_to_flush
        |> List.delete(selected_pad)
        |> do_flush_auto_flow_queues(state)
    end
  end

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
