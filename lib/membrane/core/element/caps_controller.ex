defmodule Membrane.Core.Element.CapsController do
  @moduledoc false

  # Module handling caps received on input pads.

  use Bunch

  alias Membrane.{Caps, Pad}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, InputQueue, PlaybackQueue, State}
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @doc """
  Handles incoming caps: either stores them in InputQueue, or executes element callback.
  """
  @spec handle_caps(Pad.ref_t(), Caps.t(), State.t()) :: State.t()
  def handle_caps(pad_ref, caps, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      %{direction: :input} = data
      Telemetry.report_metric(:caps, 1, inspect(pad_ref))

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
    else
      pad: {:error, :unknown_pad} ->
        # We've got caps from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_caps(pad_ref, caps, &1), state)
    end
  end

  @spec exec_handle_caps(Pad.ref_t(), Caps.t(), params :: map, State.t()) :: State.t()
  def exec_handle_caps(pad_ref, caps, params \\ %{}, state) do
    require CallbackContext.Caps

    %{parents_with_pads: parents_with_pads, name: pad_name} = PadModel.get_data!(state, pad_ref)

    context = &CallbackContext.Caps.from_state(&1, pad: pad_ref)

    :ok = ensure_caps_match(:input, [{state.module, pad_name} | parents_with_pads], caps)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_caps,
        ActionHandler,
        %{context: context} |> Map.merge(params),
        [pad_ref, caps],
        state
      )

    PadModel.set_data!(state, pad_ref, :caps, caps)
  end

  @spec ensure_caps_match(Pad.direction_t(), [{module(), Pad.name_t()}], Caps.t()) :: :ok
  def ensure_caps_match(direction, modules_with_pads, caps) do
    for {module, pad_name} <- modules_with_pads do
      if not module.caps_match?(pad_name, caps) do
        raise Membrane.CapsMatchError, """
        Received caps: #{inspect(caps)} that are not matching caps_pattern in
        def_#{direction}_pad for pad #{inspect(pad_name)} in #{inspect(module)}
        """
      end
    end

    :ok
  end
end
