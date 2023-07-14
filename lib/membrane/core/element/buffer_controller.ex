defmodule Membrane.Core.Element.BufferController do
  @moduledoc false

  # Module handling buffers incoming through input pads.

  use Bunch

  alias Membrane.{Buffer, Pad}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    DemandHandler,
    EventController,
    InputQueue,
    PlaybackQueue,
    State
  }

  alias Membrane.Core.Element.DemandController.AutoFlowUtils
  alias Membrane.Core.Telemetry

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry

  @doc """
  Handles incoming buffer: either stores it in InputQueue, or executes element's
  callback. Also calls `Membrane.Core.Element.DemandHandler.supply_demand/2`
  to check if there are any unsupplied demands.
  """
  @spec handle_buffer(Pad.ref(), [Buffer.t()] | Buffer.t(), State.t()) :: State.t()
  def handle_buffer(pad_ref, buffers, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      %{
        direction: :input,
        start_of_stream?: start_of_stream?,
        stalker_metrics: stalker_metrics
      } = data

      :atomics.add(stalker_metrics.total_buffers, 1, length(buffers))

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

  @spec do_handle_buffer(Pad.ref(), PadModel.pad_data(), [Buffer.t()] | Buffer.t(), State.t()) ::
          State.t()
  defp do_handle_buffer(pad_ref, %{flow_control: :auto} = data, buffers, state) do
    %{demand: demand, demand_unit: demand_unit, stalker_metrics: stalker_metrics} = data
    buf_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)

    state = PadModel.set_data!(state, pad_ref, :demand, demand - buf_size)
    :atomics.put(stalker_metrics.demand, 1, demand - buf_size)

    state = AutoFlowUtils.auto_adjust_atomic_demand(pad_ref, state)
    exec_buffer_callback(pad_ref, buffers, state)
  end

  defp do_handle_buffer(pad_ref, %{flow_control: :manual} = data, buffers, state) do
    %{input_queue: old_input_queue} = data

    input_queue = InputQueue.store(old_input_queue, buffers)
    state = PadModel.set_data!(state, pad_ref, :input_queue, input_queue)

    if old_input_queue |> InputQueue.empty?() do
      DemandHandler.supply_demand(pad_ref, state)
    else
      state
    end
  end

  defp do_handle_buffer(pad_ref, %{flow_control: :push}, buffers, state) do
    exec_buffer_callback(pad_ref, buffers, state)
  end

  @doc """
  Executes `handle_buffers_batch` callback.
  """
  @spec exec_buffer_callback(
          Pad.ref(),
          [Buffer.t()] | Buffer.t(),
          State.t()
        ) :: State.t()
  def exec_buffer_callback(pad_ref, buffers, %State{type: :filter} = state) do
    Telemetry.report_metric("buffer", 1, inspect(pad_ref))

    do_exec_buffer_callback(pad_ref, buffers, state)
  end

  def exec_buffer_callback(pad_ref, buffers, %State{type: type} = state)
      when type in [:sink, :endpoint] do
    Telemetry.report_metric(:buffer, length(List.wrap(buffers)))
    Telemetry.report_bitrate(buffers)

    do_exec_buffer_callback(pad_ref, buffers, state)
  end

  defp do_exec_buffer_callback(pad_ref, buffers, state) do
    CallbackHandler.exec_and_handle_callback(
      :handle_buffers_batch,
      ActionHandler,
      %{context: &CallbackContext.from_state/1},
      [pad_ref, buffers],
      state
    )
  end
end
