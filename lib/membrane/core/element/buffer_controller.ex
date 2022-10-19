defmodule Membrane.Core.Element.BufferController do
  @moduledoc false

  # Module handling buffers incoming through input pads.

  use Bunch

  alias Membrane.{Buffer, Pad}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    DemandController,
    DemandHandler,
    EventController,
    InputQueue,
    PlaybackQueue,
    State
  }

  alias Membrane.Core.Telemetry
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry

  @doc """
  Handles incoming buffer: either stores it in InputQueue, or executes element's
  callback. Also calls `Membrane.Core.Element.DemandHandler.supply_demand/2`
  to check if there are any unsupplied demands.
  """
  @spec handle_buffer(Pad.ref_t(), [Buffer.t()] | Buffer.t(), State.t()) :: State.t()
  def handle_buffer(pad_ref, buffers, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      %{direction: :input, start_of_stream?: start_of_stream?} = data

      state =
        if start_of_stream? do
          state
        else
          EventController.handle_start_of_stream(pad_ref, state)
        end

      do_handle_buffer(pad_ref, data, buffers, state)
    else
      pad: {:error, :unknown_pad} ->
        # We've got a buffer from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_buffer(pad_ref, buffers, &1), state)
    end
  end

  @spec do_handle_buffer(Pad.ref_t(), PadModel.pad_data_t(), [Buffer.t()] | Buffer.t(), State.t()) ::
          State.t()
  defp do_handle_buffer(pad_ref, %{mode: :pull, demand_mode: :auto} = data, buffers, state) do
    %{demand: demand, demand_unit: demand_unit} = data
    buf_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)
    state = PadModel.set_data!(state, pad_ref, :demand, demand - buf_size)
    state = DemandController.send_auto_demand_if_needed(pad_ref, state)
    exec_buffer_callback(pad_ref, buffers, state)
  end

  defp do_handle_buffer(pad_ref, %{mode: :pull} = data, buffers, state) do
    %{input_queue: old_input_queue} = data
    input_queue = InputQueue.store(old_input_queue, buffers)
    state = PadModel.set_data!(state, pad_ref, :input_queue, input_queue)

    if old_input_queue |> InputQueue.empty?() do
      DemandHandler.supply_demand(pad_ref, state)
    else
      state
    end
  end

  defp do_handle_buffer(pad_ref, _data, buffers, state) do
    exec_buffer_callback(pad_ref, buffers, state)
  end

  @doc """
  Executes `handle_process_list` or `handle_write_list` callback.
  """
  @spec exec_buffer_callback(
          Pad.ref_t(),
          [Buffer.t()] | Buffer.t(),
          State.t()
        ) :: State.t()
  def exec_buffer_callback(pad_ref, buffers, %State{type: :filter} = state) do
    require CallbackContext.Process
    Telemetry.report_metric("buffer", 1, inspect(pad_ref))

    CallbackHandler.exec_and_handle_callback(
      :handle_process_list,
      ActionHandler,
      %{context: &CallbackContext.Process.from_state/1},
      [pad_ref, buffers],
      state
    )
  end

  def exec_buffer_callback(pad_ref, buffers, %State{type: type} = state)
      when type in [:sink, :endpoint] do
    require CallbackContext.Write

    Telemetry.report_metric(:buffer, length(List.wrap(buffers)))
    Telemetry.report_bitrate(buffers)

    CallbackHandler.exec_and_handle_callback(
      :handle_write_list,
      ActionHandler,
      %{context: &CallbackContext.Write.from_state/1},
      [pad_ref, buffers],
      state
    )
  end
end
