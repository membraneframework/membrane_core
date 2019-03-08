defmodule Membrane.Core.Element.CapsController do
  @moduledoc false
  # Module handling caps received on input pads.

  alias Membrane.{Caps, Core, Element}
  alias Core.{CallbackHandler, InputBuffer}
  alias Core.Element.{ActionHandler, PadModel, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.Caps
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles incoming caps: either stores them in InputBuffer, or executes element callback.
  """
  @spec handle_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def handle_caps(pad_ref, caps, state) do
    PadModel.assert_data!(pad_ref, %{direction: :input}, state)
    data = PadModel.get_data!(pad_ref, state)

    if data.mode == :pull and not (data.buffer |> InputBuffer.empty?()) do
      PadModel.update_data(
        pad_ref,
        :buffer,
        &(&1 |> InputBuffer.store(:caps, caps)),
        state
      )
    else
      exec_handle_caps(pad_ref, caps, state)
    end
  end

  @spec exec_handle_caps(Pad.ref_t(), Caps.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  def exec_handle_caps(pad_ref, caps, params \\ %{}, state) do
    %{accepted_caps: accepted_caps} = PadModel.get_data!(pad_ref, state)

    context = CallbackContext.Caps.from_state(state, pad: pad_ref)

    withl match: true <- Caps.Matcher.match?(accepted_caps, caps),
          callback:
            {:ok, state} <-
              CallbackHandler.exec_and_handle_callback(
                :handle_caps,
                ActionHandler,
                params,
                [pad_ref, caps, context],
                state
              ) do
      {:ok, PadModel.set_data!(pad_ref, :caps, caps, state)}
    else
      match: false ->
        warn_error(
          """
          Received caps: #{inspect(caps)} that are not specified in def_input_pads
          for pad #{inspect(pad_ref)}. Specs of accepted caps are:
          #{inspect(accepted_caps, pretty: true)}
          """,
          :invalid_caps,
          state
        )

      callback: {{:error, reason}, state} ->
        warn_error("Error while handling caps", reason, state)
    end
  end
end
