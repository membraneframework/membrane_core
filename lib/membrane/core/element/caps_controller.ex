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

  @type caps_validation_param_t() :: {module(), Pad.name_t()}
  @type caps_validation_params_t() :: [caps_validation_param_t()]

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

    %{ancestors_with_pads: ancestors_with_pads, name: pad_name} =
      PadModel.get_data!(state, pad_ref)

    context = &CallbackContext.Caps.from_state(&1, pad: pad_ref)

    :ok = validate_caps!(:input, [{state.module, pad_name} | ancestors_with_pads], caps)

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

  @spec validate_caps!(Pad.direction_t(), caps_validation_params_t(), Caps.t()) :: :ok
  def validate_caps!(direction, modules_with_pads, caps) do
    unless is_struct(caps) do
      raise Membrane.CapsError, """
      Caps: #{inspect(caps)} are not a struct, even though they have to be
      """
    end

    for {module, pad_name} <- modules_with_pads do
      unless module.membrane_caps_match?(pad_name, caps) do
        raise Membrane.CapsError, """
        Caps: #{inspect(caps)} are not matching caps pattern in def_#{direction}_pad
        for pad #{inspect(pad_name)} in #{inspect(module)}
        """
      end
    end

    :ok
  end
end
