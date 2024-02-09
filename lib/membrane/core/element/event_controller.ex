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
    PlaybackQueue,
    State
  }

  alias Membrane.Core.Element.DemandController.AutoFlowUtils

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

      cond do
        # events goes to the manual flow control input queue
        not Event.async?(event) and buffers_before_event_present?(data) ->
          PadModel.update_data!(
            state,
            pad_ref,
            :input_queue,
            &InputQueue.store(&1, :event, event)
          )

        # event goes to the auto flow control queue
        pad_ref in state.awaiting_auto_input_pads ->
          AutoFlowUtils.store_event_in_queue(pad_ref, event, state)

        true ->
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
  def exec_handle_event(pad_ref, event, params \\ %{}, state)

  def exec_handle_event(pad_ref, %Events.StartOfStream{} = event, params, state) do
    state = PadModel.set_data!(state, pad_ref, :start_of_stream?, true)
    :ok = check_sync(state)

    new_params =
      Map.merge(params, %{
        context: &CallbackContext.from_state/1,
        direction: PadModel.get_data!(state, pad_ref, :direction)
      })

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_start_of_stream,
        ActionHandler,
        new_params,
        [pad_ref],
        state
      )

    Message.send(
      state.parent_pid,
      :stream_management_event,
      [state.name, pad_ref, event, []]
    )

    state
  end

  def exec_handle_event(pad_ref, %Events.EndOfStream{} = event, params, state) do
    if PadModel.get_data!(state, pad_ref, :end_of_stream?) do
      Membrane.Logger.debug("Ignoring end of stream as it has already arrived before")
      state
    else
      Membrane.Logger.debug("Received end of stream on pad #{inspect(pad_ref)}")

      state =
        PadModel.set_data!(state, pad_ref, :end_of_stream?, true)
        |> Map.update!(:awaiting_auto_input_pads, &MapSet.delete(&1, pad_ref))
        |> Map.update!(:auto_input_pads, &List.delete(&1, pad_ref))

      %{
        start_of_stream?: start_of_stream?,
        direction: direction
      } = PadModel.get_data!(state, pad_ref)

      event_params = [start_of_stream_received?: start_of_stream?]

      new_params =
        Map.merge(params, %{
          context: &CallbackContext.from_state(&1, event_params),
          direction: direction
        })

      state =
        CallbackHandler.exec_and_handle_callback(
          :handle_end_of_stream,
          ActionHandler,
          new_params,
          [pad_ref],
          state
        )

      Message.send(
        state.parent_pid,
        :stream_management_event,
        [state.name, pad_ref, event, event_params]
      )

      state
    end
  end

  def exec_handle_event(pad_ref, event, params, state) do
    data = PadModel.get_data!(state, pad_ref)

    params =
      %{context: &CallbackContext.from_state/1, direction: data.direction}
      |> Map.merge(params)

    args = [pad_ref, event]
    CallbackHandler.exec_and_handle_callback(:handle_event, ActionHandler, params, args, state)
  end

  defp check_sync(state) do
    if state.pads_data
       |> Map.values()
       |> Enum.filter(&(&1.direction == :input))
       |> Enum.all?(& &1.start_of_stream?) do
      :ok = Sync.sync(state.synchronization.stream_sync)
    end

    :ok
  end

  defp buffers_before_event_present?(pad_data) do
    pad_data.input_queue && not InputQueue.empty?(pad_data.input_queue)
  end
end
