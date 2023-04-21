defmodule Membrane.Core.Element.DemandHandler do
  @moduledoc false

  # Module handling demands requested on output pads.

  alias Membrane.Core.Element.{
    BufferController,
    DemandController,
    EventController,
    InputQueue,
    State,
    StreamFormatController
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message

  @handle_demand_loop_limit 20

  @doc """
  Called when redemand action was returned.
    * If element is currently supplying demand, it means that after finishing `supply_demand` it will call
      `handle_delayed_demands`.
    * If element isn't supplying demand at the moment and there's some unsupplied demand on the given
      output, `handle_demand` is invoked right away, so that the demand can be synchronously supplied.
  """
  @spec handle_redemand(Pad.ref(), State.t()) :: State.t()
  def handle_redemand(pad_ref, %State{supplying_demand?: true} = state) do
    Map.update!(state, :delayed_demands, &MapSet.put(&1, {pad_ref, :redemand}))
  end

  def handle_redemand(pad_ref, %State{} = state) do
    do_handle_redemand(pad_ref, state)
    |> handle_delayed_demands()
  end

  defp do_handle_redemand(pad_ref, state) do
    state = %{state | supplying_demand?: true}
    state = DemandController.exec_handle_demand(pad_ref, state)
    %{state | supplying_demand?: false}
  end

  @doc """
  If element is not supplying demand currently, this function supplies
  demand right away by taking buffers from the InputQueue of the given input pad
  and passing it to proper controllers.

  If element is currently supplying demand it delays supplying demand until all
  current processing is finished.

  This is necessary due to the case when one requests a demand action while previous
  demand is being supplied. This could lead to a situation where buffers are taken
  from InputQueue and passed to callbacks, while buffers being currently supplied
  have not been processed yet, and therefore to changing order of buffers.

  The `size` argument can be passed optionally to update the demand on the pad
  before proceeding to supplying it.
  """
  @spec supply_demand(
          Pad.ref(),
          size :: non_neg_integer | (non_neg_integer() -> non_neg_integer()),
          State.t()
        ) :: State.t()
  def supply_demand(pad_ref, size, state) do
    state = update_demand(pad_ref, size, state)
    supply_demand(pad_ref, state)
  end

  @spec supply_demand(Pad.ref(), State.t()) :: State.t()
  def supply_demand(pad_ref, %State{supplying_demand?: true} = state) do
    Map.update!(state, :delayed_demands, &MapSet.put(&1, {pad_ref, :supply}))
  end

  def supply_demand(pad_ref, state) do
    do_supply_demand(pad_ref, state)
    |> handle_delayed_demands()
  end

  defp do_supply_demand(pad_ref, state) do
    # marking is state that actual demand supply has been started (note changing back to false when finished)
    state = %State{state | supplying_demand?: true}

    pad_data = state |> PadModel.get_data!(pad_ref)

    {{_queue_status, popped_data}, new_input_queue} =
      InputQueue.take(pad_data.input_queue, pad_data.demand_snapshot)

    state = PadModel.set_data!(state, pad_ref, :input_queue, new_input_queue)
    state = handle_input_queue_output(pad_ref, popped_data, state)
    %State{state | supplying_demand?: false}
  end

  defp update_demand(pad_ref, size, state) when is_integer(size) do
    PadModel.set_data!(state, pad_ref, :demand_snapshot, size)
  end

  defp update_demand(pad_ref, size_fun, state) when is_function(size_fun) do
    demand_snapshot = PadModel.get_data!(state, pad_ref, :demand_snapshot)
    new_demand_snapshot = size_fun.(demand_snapshot)

    if new_demand_snapshot < 0 do
      raise Membrane.ElementError,
            "Demand altering function requested negative demand on pad #{inspect(pad_ref)} in #{state.module}"
    end

    PadModel.set_data!(state, pad_ref, :demand_snapshot, new_demand_snapshot)
  end

  @spec handle_delayed_demands(State.t()) :: State.t()
  def handle_delayed_demands(%State{} = state) do
    # Taking random element of `:delayed_demands` is done to keep data flow
    # balanced among pads, i.e. to prevent situation where demands requested by
    # one pad are supplied right away while another one is waiting for buffers
    # potentially for a long time.

    cond do
      state.supplying_demand? ->
        raise "Cannot handle delayed demands while already supplying demand"

      state.handle_demand_loop_counter >= @handle_demand_loop_limit ->
        Message.self(:resume_handle_demand_loop)
        %{state | handle_demand_loop_counter: 0}

      state.delayed_demands == MapSet.new() ->
        %{state | handle_demand_loop_counter: 0}

      true ->
        [{pad_ref, action} = entry] = Enum.take_random(state.delayed_demands, 1)

        state =
          state
          |> Map.update!(:delayed_demands, &MapSet.delete(&1, entry))
          |> Map.update!(:handle_demand_loop_counter, &(&1 + 1))

        case action do
          :supply -> supply_demand(pad_ref, state)
          :redemand -> handle_redemand(pad_ref, state)
        end
    end
  end

  @spec handle_input_queue_output(
          Pad.ref(),
          [InputQueue.output_value()],
          State.t()
        ) :: State.t()
  defp handle_input_queue_output(pad_ref, queue_output, state) do
    Enum.reduce(queue_output, state, fn item, state ->
      do_handle_input_queue_output(pad_ref, item, state)
    end)
  end

  @spec do_handle_input_queue_output(
          Pad.ref(),
          InputQueue.output_value(),
          State.t()
        ) :: State.t()
  defp do_handle_input_queue_output(pad_ref, {:event, e}, state),
    do: EventController.exec_handle_event(pad_ref, e, state)

  defp do_handle_input_queue_output(pad_ref, {:stream_format, stream_format}, state),
    do: StreamFormatController.exec_handle_stream_format(pad_ref, stream_format, state)

  defp do_handle_input_queue_output(
         pad_ref,
         {:buffers, buffers, _inbound_metric_buf_size, outbound_metric_buf_size},
         state
       ) do
    state =
      PadModel.update_data!(state, pad_ref, :demand_snapshot, &(&1 - outbound_metric_buf_size))

    BufferController.exec_buffer_callback(pad_ref, buffers, state)
  end
end
