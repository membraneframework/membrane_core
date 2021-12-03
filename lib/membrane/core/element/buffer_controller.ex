defmodule Membrane.Core.Element.BufferController do
  @moduledoc false

  # Module handling buffers incoming through input pads.

  use Bunch

  alias Membrane.{Buffer, Pad}
  alias Membrane.Core.{CallbackHandler, InputBuffer, Telemetry}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, DemandController, DemandHandler, State}
  alias Membrane.Core.Telemetry
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry

  @doc """
  Handles incoming buffer: either stores it in InputBuffer, or executes element's
  callback. Also calls `Membrane.Core.Element.DemandHandler.supply_demand/2`
  to check if there are any unsupplied demands.
  """
  @spec handle_buffer(Pad.ref_t(), [Buffer.t()] | Buffer.t(), State.t()) :: State.stateful_try_t()
  def handle_buffer(pad_ref, buffers, state) do
    %{direction: :input} = data = PadModel.get_data!(state, pad_ref)
    do_handle_buffer(pad_ref, data, buffers, state)
  end

  @spec do_handle_buffer(Pad.ref_t(), PadModel.pad_data_t(), [Buffer.t()] | Buffer.t(), State.t()) ::
          State.stateful_try_t()
  defp do_handle_buffer(pad_ref, %{mode: :pull, demand_mode: :auto} = data, buffers, state) do
    %{demand: demand, demand_unit: demand_unit} = data
    buf_size = Buffer.Metric.from_unit(demand_unit).buffers_size(buffers)
    state = PadModel.set_data!(state, pad_ref, :demand, demand - buf_size)
    state = DemandController.send_auto_demand_if_needed(pad_ref, state)
    exec_buffer_handler(pad_ref, buffers, state)
  end

  defp do_handle_buffer(pad_ref, %{mode: :pull} = data, buffers, state) do
    %{input_buf: old_input_buf} = data
    input_buf = InputBuffer.store(old_input_buf, buffers)
    state = PadModel.set_data!(state, pad_ref, :input_buf, input_buf)

    if old_input_buf |> InputBuffer.empty?() do
      DemandHandler.supply_demand(pad_ref, state)
    else
      {:ok, state}
    end
  end

  defp do_handle_buffer(pad_ref, _data, buffers, state) do
    exec_buffer_handler(pad_ref, buffers, state)
  end

  @doc """
  Executes `handle_process` or `handle_write_list` callback.
  """
  @spec exec_buffer_handler(
          Pad.ref_t(),
          [Buffer.t()] | Buffer.t(),
          State.t()
        ) :: State.stateful_try_t()
  def exec_buffer_handler(pad_ref, buffers, %State{type: :filter} = state) do
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

  def exec_buffer_handler(pad_ref, buffers, %State{type: :sink} = state) do
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
