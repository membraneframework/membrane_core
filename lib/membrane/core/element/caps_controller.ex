defmodule Membrane.Core.Element.CapsController do
  @moduledoc false

  # Module handling caps received on input pads.

  use Bunch

  alias Membrane.{Caps, Pad}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, InputQueue, State}
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @doc """
  Handles incoming caps: either stores them in InputQueue, or executes element callback.
  """
  @spec handle_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.t()
  def handle_caps(pad_ref, caps, state) do
    Telemetry.report_metric(:caps, 1, inspect(pad_ref))

    PadModel.assert_data!(state, pad_ref, %{direction: :input})
    data = PadModel.get_data!(state, pad_ref)

    queue = data.input_queue

    if queue && not InputQueue.empty?(queue) do
      PadModel.set_data!(
        state,
        pad_ref,
        :input_queue,
        InputQueue.store(queue, :caps, caps)
      )
    else
      exec_handle_caps(pad_ref, caps, state)
    end
  end

  @spec exec_handle_caps(Pad.ref_t(), Caps.t(), params :: map, State.t()) :: State.t()
  def exec_handle_caps(pad_ref, caps, params \\ %{}, state) do
    require CallbackContext.Caps
    %{accepted_caps: accepted_caps} = PadModel.get_data!(state, pad_ref)
    context = &CallbackContext.Caps.from_state(&1, pad: pad_ref)

    if Caps.Matcher.match?(accepted_caps, caps) do
      state =
        CallbackHandler.exec_and_handle_callback(
          :handle_caps,
          ActionHandler,
          %{context: context} |> Map.merge(params),
          [pad_ref, caps],
          state
        )

      PadModel.set_data!(state, pad_ref, :caps, caps)
    else
      raise """
      Received caps: #{inspect(caps)} that are not specified in def_input_pad
      for pad #{inspect(pad_ref)}. Specs of accepted caps are:
      #{inspect(accepted_caps, pretty: true)}
      """
    end
  end
end
