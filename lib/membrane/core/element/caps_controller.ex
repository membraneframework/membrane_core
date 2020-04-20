defmodule Membrane.Core.Element.CapsController do
  @moduledoc false

  # Module handling caps received on input pads.

  use Bunch
  require Logger
  require Membrane.Element.CallbackContext.Caps
  require Membrane.Core.Child.PadModel
  alias Membrane.{Caps, Pad}
  alias Membrane.Core.{CallbackHandler, InputBuffer}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext

  @doc """
  Handles incoming caps: either stores them in InputBuffer, or executes element callback.
  """
  @spec handle_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def handle_caps(pad_ref, caps, state) do
    PadModel.assert_data!(state, pad_ref, %{direction: :input})
    data = PadModel.get_data!(state, pad_ref)

    if data.mode == :pull and not (data.input_buf |> InputBuffer.empty?()) do
      state |> PadModel.update_data(pad_ref, :input_buf, &(&1 |> InputBuffer.store(:caps, caps)))
    else
      exec_handle_caps(pad_ref, caps, state)
    end
  end

  @spec exec_handle_caps(Pad.ref_t(), Caps.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  def exec_handle_caps(pad_ref, caps, params \\ %{}, state) do
    %{accepted_caps: accepted_caps} = PadModel.get_data!(state, pad_ref)

    context = &CallbackContext.Caps.from_state(&1, pad: pad_ref)

    withl match: true <- Caps.Matcher.match?(accepted_caps, caps),
          callback:
            {:ok, state} <-
              CallbackHandler.exec_and_handle_callback(
                :handle_caps,
                ActionHandler,
                %{context: context} |> Map.merge(params),
                [pad_ref, caps],
                state
              ) do
      {:ok, PadModel.set_data!(state, pad_ref, :caps, caps)}
    else
      match: false ->
        Logger.error("""
        Received caps: #{inspect(caps)} that are not specified in def_input_pad
        for pad #{inspect(pad_ref)}. Specs of accepted caps are:
        #{inspect(accepted_caps, pretty: true)}
        """)

        {{:error, :invalid_caps}, state}

      callback: {{:error, reason}, state} ->
        {{:error, reason}, state}
    end
  end
end
