defmodule Membrane.Core.Element.EventController do
  @moduledoc false

  # Module handling events incoming through input pads.

  use Bunch

  alias Membrane.{Event, Pad, Sync}
  alias Membrane.Core.{CallbackHandler, Events, Message, Telemetry}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    InputQueue,
    PadController,
    PlaybackQueue,
    State
  }

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @spec handle_start_of_stream(Pad.ref(), State.t()) :: State.t()
  def handle_start_of_stream(pad_ref, state) do
    handle_event(pad_ref, %Events.StartOfStream{}, state)
  end

  @doc """
  Handles incoming event: either stores it in InputQueue, or executes element callback.
  Extra checks and tasks required by special events such as `:start_of_stream`
  or `:end_of_stream` are performed.
  """
  @spec handle_event(Pad.ref(), Event.t(), State.t()) :: State.t()
  def handle_event(pad_ref, event, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      Telemetry.report_metric(:event, 1, inspect(pad_ref))

      if not Event.async?(event) and buffers_before_event_present?(data) do
        PadModel.update_data!(
          state,
          pad_ref,
          :input_queue,
          &InputQueue.store(&1, :event, event)
        )
      else
        exec_handle_event(pad_ref, event, state)
      end
    else
      pad: {:error, :unknown_pad} ->
        # We've got an event from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_event(pad_ref, event, &1), state)
    end
  end

  @spec exec_handle_event(Pad.ref(), Event.t(), params :: map, State.t()) :: State.t()
  def exec_handle_event(pad_ref, event, params \\ %{}, state) do
    case handle_special_event(pad_ref, event, state) do
      {:handle, state} ->
        :ok = check_sync(event, state)
        do_exec_handle_event(pad_ref, event, params, state)

      {:ignore, state} ->
        state
    end
  end

  @spec do_exec_handle_event(Pad.ref(), Event.t(), params :: map, State.t()) :: State.t()
  defp do_exec_handle_event(pad_ref, %event_type{} = event, params, state)
       when event_type in [Events.StartOfStream, Events.EndOfStream] do
    data = PadModel.get_data!(state, pad_ref)
    callback = stream_event_to_callback(event)
    context = stream_event_to_callback_context(event, pad_ref)

    new_params =
      Map.merge(params, %{
        context: context,
        direction: data.direction
      })

    state =
      CallbackHandler.exec_and_handle_callback(
        callback,
        ActionHandler,
        new_params,
        [pad_ref],
        state
      )

    event_opts = stream_event_to_parent_message_opts(event, pad_ref, state)

    Message.send(state.parent_pid, :stream_management_event, [
      state.name,
      pad_ref,
      event,
      event_opts
    ])

    state
  end

  defp do_exec_handle_event(pad_ref, event, params, state) do
    data = PadModel.get_data!(state, pad_ref)

    params =
      %{context: &CallbackContext.from_state/1, direction: data.direction}
      |> Map.merge(params)

    args = [pad_ref, event]
    CallbackHandler.exec_and_handle_callback(:handle_event, ActionHandler, params, args, state)
  end

  defp stream_event_to_callback_context(%Events.StartOfStream{}, _pad_ref),
    do: &CallbackContext.from_state/1

  defp stream_event_to_callback_context(%Events.EndOfStream{}, pad_ref) do
    &CallbackContext.from_state(&1,
      preceded_by_start_of_stream?: PadModel.get_data!(&1, pad_ref, :start_of_stream?)
    )
  end

  defp stream_event_to_parent_message_opts(%Events.StartOfStream{}, _pad_ref, _state), do: []

  defp stream_event_to_parent_message_opts(%Events.EndOfStream{}, pad_ref, state),
    do: [preceded_by_start_of_stream?: PadModel.get_data!(state, pad_ref, :start_of_stream?)]

  defp check_sync(%Events.StartOfStream{}, state) do
    if state.pads_data
       |> Map.values()
       |> Enum.filter(&(&1.direction == :input))
       |> Enum.all?(& &1.start_of_stream?) do
      :ok = Sync.sync(state.synchronization.stream_sync)
    end

    :ok
  end

  defp check_sync(_event, _state) do
    :ok
  end

  @spec handle_special_event(Pad.ref(), Event.t(), State.t()) ::
          {:handle | :ignore, State.t()}
  defp handle_special_event(pad_ref, %Events.StartOfStream{}, state) do
    Membrane.Logger.debug("received start of stream")
    state = PadModel.set_data!(state, pad_ref, :start_of_stream?, true)
    {:handle, state}
  end

  defp handle_special_event(pad_ref, %Events.EndOfStream{}, state) do
    if PadModel.get_data!(state, pad_ref, :end_of_stream?) do
      Membrane.Logger.debug("Ignoring end of stream as it has already arrived before")
      {:ignore, state}
    else
      state = PadModel.set_data!(state, pad_ref, :end_of_stream?, true)
      state = PadController.remove_pad_associations(pad_ref, state)
      {:handle, state}
    end
  end

  defp handle_special_event(_pad_ref, _event, state), do: {:handle, state}

  defp buffers_before_event_present?(pad_data) do
    pad_data.input_queue && not InputQueue.empty?(pad_data.input_queue)
  end

  defp stream_event_to_callback(%Events.StartOfStream{}), do: :handle_start_of_stream
  defp stream_event_to_callback(%Events.EndOfStream{}), do: :handle_end_of_stream
end
