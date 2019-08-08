defmodule Membrane.Core.Element.EventController do
  @moduledoc false
  # Module handling events incoming through input pads.

  alias Membrane.{Core, Element, Event}
  alias Core.{CallbackHandler, InputBuffer, Message}
  alias Core.Element.{ActionHandler, PadModel, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.Event
  require CallbackContext.StreamManagement
  require PadModel
  require Message
  use Core.Element.Log
  use Bunch

  def handle_start_of_stream(pad_ref, state) do
    handle_event(pad_ref, %Event.StartOfStream{}, state)
  end

  @doc """
  Handles incoming event: either stores it in InputBuffer, or executes element callback.
  Extra checks and tasks required by special events such as `:start_of_stream`
  or `:end_of_stream` are performed.
  """
  @spec handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  def handle_event(pad_ref, event, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    if not Event.async?(event) && pad_data.mode == :pull && pad_data.direction == :input &&
         buffers_before_event_present?(pad_data) do
      state
      |> PadModel.update_data(pad_ref, :input_buf, &(&1 |> InputBuffer.store(:event, event)))
    else
      exec_handle_event(pad_ref, event, state)
    end
  end

  @spec exec_handle_event(Pad.ref_t(), Event.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  def exec_handle_event(pad_ref, event, params \\ %{}, state) do
    withl handle: {{:ok, :handle}, state} <- handle_special_event(pad_ref, event, state),
          exec: {:ok, state} <- do_exec_handle_event(pad_ref, event, params, state) do
      {:ok, state}
    else
      handle: {{:ok, :ignore}, state} ->
        debug("ignoring event #{inspect(event)}", state)
        {:ok, state}

      handle: {{:error, reason}, state} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)

      exec: {{:error, reason}, state} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)
    end
  end

  @spec do_exec_handle_event(Pad.ref_t(), Event.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  defp do_exec_handle_event(pad_ref, %event_type{} = event, params, state)
       when event_type in [Event.StartOfStream, Event.EndOfStream] do
    data = PadModel.get_data!(state, pad_ref)
    context = CallbackContext.StreamManagement.from_state(state)

    callback = stream_event_to_callback(event)
    new_params = Map.put(params, :direction, data.direction)
    args = [pad_ref, context]

    res =
      CallbackHandler.exec_and_handle_callback(
        callback,
        ActionHandler,
        new_params,
        args,
        state
      )

    Message.send(state.watcher, callback, [state.name, pad_ref])
    res
  end

  defp do_exec_handle_event(pad_ref, event, params, state) do
    data = PadModel.get_data!(state, pad_ref)
    context = CallbackContext.Event.from_state(state)

    new_params = Map.put(params, :direction, data.direction)
    args = [pad_ref, event, context]

    CallbackHandler.exec_and_handle_callback(
      :handle_event,
      ActionHandler,
      new_params,
      args,
      state
    )
  end

  @spec handle_special_event(Pad.ref_t(), Event.t(), State.t()) ::
          State.stateful_try_t(:handle | :ignore)
  defp handle_special_event(pad_ref, %Event.StartOfStream{}, state) do
    with %{direction: :input, start_of_stream?: false} <- PadModel.get_data!(state, pad_ref) do
      state
      |> PadModel.set_data!(pad_ref, :start_of_stream?, true)
      ~> {{:ok, :handle}, &1}
    else
      %{direction: :output} ->
        {{:error, {:received_start_of_stream_through_output, pad_ref}}, state}

      %{start_of_stream?: true} ->
        {{:error, {:start_of_stream_already_received, pad_ref}}, state}
    end
  end

  defp handle_special_event(pad_ref, %Event.EndOfStream{}, state) do
    with %{direction: :input, start_of_stream?: true, end_of_stream?: false} <-
           PadModel.get_data!(state, pad_ref) do
      state
      |> PadModel.set_data!(pad_ref, :end_of_stream?, true)
      ~> {{:ok, :handle}, &1}
    else
      %{direction: :output} ->
        {{:error, {:received_end_of_stream_through_output, pad_ref}}, state}

      %{end_of_stream?: true} ->
        {{:error, {:end_of_stream_already_received, pad_ref}}, state}

      %{start_of_stream?: false} ->
        {{:ok, :ignore}, state}
    end
  end

  defp handle_special_event(_pad_ref, _event, state), do: {{:ok, :handle}, state}

  defp buffers_before_event_present?(pad_data), do: not InputBuffer.empty?(pad_data.input_buf)

  defp stream_event_to_callback(%Event.StartOfStream{}), do: :handle_start_of_stream
  defp stream_event_to_callback(%Event.EndOfStream{}), do: :handle_end_of_stream
end
