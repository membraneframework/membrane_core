defmodule Membrane.Core.Element.DemandHandler do
  @moduledoc false

  # Module handling demands requested on output pads.

  alias Membrane.Buffer
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    BufferController,
    DemandController,
    EventController,
    InputQueue,
    State,
    StreamFormatController,
    Toilet
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Logger

  @doc """
  Called when redemand action was returned.
    * If element is currently supplying demand, it means that after finishing `supply_demand` it will call
      `handle_delayed_demands`.
    * If element isn't supplying demand at the moment and there's some unsupplied demand on the given
      output, `handle_demand` is invoked right away, so that the demand can be synchronously supplied.
  """
  @spec handle_redemand(Pad.ref_t(), State.t()) :: State.t()
  def handle_redemand(pad_ref, %State{supplying_demand?: true} = state) do
    Map.update!(state, :delayed_demands, &MapSet.put(&1, {pad_ref, :redemand}))
  end

  def handle_redemand(pad_ref, state) do
    DemandController.handle_demand(pad_ref, 0, state)
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
          Pad.ref_t(),
          size :: non_neg_integer | (non_neg_integer() -> non_neg_integer()),
          State.t()
        ) :: State.t()
  def supply_demand(pad_ref, size, state) do
    state = update_demand(pad_ref, size, state)
    supply_demand(pad_ref, state)
  end

  @spec supply_demand(Pad.ref_t(), State.t()) :: State.t()
  def supply_demand(pad_ref, %State{supplying_demand?: true} = state) do
    Map.update!(state, :delayed_demands, &MapSet.put(&1, {pad_ref, :supply}))
  end

  def supply_demand(pad_ref, state) do
    state = do_supply_demand(pad_ref, state)
    handle_delayed_demands(state)
  end

  defp do_supply_demand(pad_ref, state) do
    # marking is state that actual demand supply has been started (note changing back to false when finished)
    state = %State{state | supplying_demand?: true}

    pad_data = state |> PadModel.get_data!(pad_ref)

    {{_queue_status, data}, new_input_queue} =
      InputQueue.take_and_demand(
        pad_data.input_queue,
        pad_data.demand,
        pad_data.pid,
        pad_data.other_ref
      )

    state = PadModel.set_data!(state, pad_ref, :input_queue, new_input_queue)
    state = handle_input_queue_output(pad_ref, data, state)
    %State{state | supplying_demand?: false}
  end

  @doc """
  Decreases the demand on the output by the size of outgoing buffers. Checks for the toilet
  overflow if the toilet is enabled.
  """
  @spec handle_outgoing_buffers(
          Pad.ref_t(),
          PadModel.pad_data_t(),
          [Buffer.t()],
          State.t()
        ) :: State.t()
  def handle_outgoing_buffers(pad_ref, %{mode: :pull} = data, buffers, state) do
    %{other_demand_unit: other_demand_unit, demand: demand} = data
    buf_size = Buffer.Metric.from_unit(other_demand_unit).buffers_size(buffers)
    PadModel.set_data!(state, pad_ref, :demand, demand - buf_size)
  end

  def handle_outgoing_buffers(
        pad_ref,
        %{
          mode: :push,
          toilet: toilet
        } = data,
        buffers,
        state
      )
      when toilet != nil do
    %{other_demand_unit: other_demand_unit} = data
    buf_size = Buffer.Metric.from_unit(other_demand_unit).buffers_size(buffers)

    case Toilet.fill(toilet, buf_size) do
      {:ok, toilet} ->
        PadModel.set_data!(state, pad_ref, :toilet, toilet)

      {:overflow, _toilet} ->
        # if the toilet has overflowed, we remove it so it didn't overflow again
        # and let the parent handle that situation by unlinking this output pad or crashing
        PadModel.set_data!(state, pad_ref, :toilet, nil)
    end
  end

  def handle_outgoing_buffers(_pad_ref, _pad_data, _buffers, state) do
    state
  end

  defp update_demand(pad_ref, size, state) when is_integer(size) do
    PadModel.set_data!(state, pad_ref, :demand, size)
  end

  defp update_demand(pad_ref, size_fun, state) when is_function(size_fun) do
    demand = PadModel.get_data!(state, pad_ref, :demand)
    new_demand = size_fun.(demand)

    if new_demand < 0 do
      raise Membrane.ElementError,
            "Demand altering function requested negative demand on pad #{inspect(pad_ref)} in #{state.module}"
    end

    PadModel.set_data!(state, pad_ref, :demand, new_demand)
  end

  @spec handle_delayed_demands(State.t()) :: State.t()
  defp handle_delayed_demands(%State{delayed_demands: delayed_demands} = state) do
    # Taking random element of `:delayed_demands` is done to keep data flow
    # balanced among pads, i.e. to prevent situation where demands requested by
    # one pad are supplied right away while another one is waiting for buffers
    # potentially for a long time.
    case Enum.take_random(state.delayed_demands, 1) do
      [] ->
        state

      [{pad_ref, action} = entry] ->
        state = %State{state | delayed_demands: MapSet.delete(delayed_demands, entry)}

        state =
          case action do
            :supply -> do_supply_demand(pad_ref, state)
            :redemand -> handle_redemand(pad_ref, state)
          end

        handle_delayed_demands(state)
    end
  end

  @spec handle_input_queue_output(
          Pad.ref_t(),
          [InputQueue.output_value_t()],
          State.t()
        ) :: State.t()
  defp handle_input_queue_output(pad_ref, data, state) do
    Enum.reduce(data, state, fn v, state ->
      do_handle_input_queue_output(pad_ref, v, state)
    end)
  end

  @spec do_handle_input_queue_output(
          Pad.ref_t(),
          InputQueue.output_value_t(),
          State.t()
        ) :: State.t()
  defp do_handle_input_queue_output(pad_ref, {:event, e}, state),
    do: EventController.exec_handle_event(pad_ref, e, state)

  defp do_handle_input_queue_output(pad_ref, {:stream_format, c}, state),
    do: StreamFormatController.exec_handle_stream_format(pad_ref, c, state)

  defp do_handle_input_queue_output(
         pad_ref,
         {:buffers, buffers, size},
         state
       ) do
    state = PadModel.update_data!(state, pad_ref, :demand, &(&1 - size))

    if toilet = PadModel.get_data!(state, pad_ref, :toilet) do
      Toilet.drain(toilet, size)
    end

    BufferController.exec_buffer_callback(pad_ref, buffers, state)
  end
end
