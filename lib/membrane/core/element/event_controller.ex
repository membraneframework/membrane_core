defmodule Membrane.Core.Element.EventController do
  @moduledoc false
  # Module handling events incoming through input pads.

  alias Membrane.{Core, Element, Event, Sync}
  alias Core.{CallbackHandler, InputBuffer}
  alias Core.Element.{ActionHandler, PadModel, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.Event
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles incoming event: either stores it in InputBuffer, or executes element callback.
  Extra checks and tasks required by special events such as `:start_of_stream`
  or `:end_of_stream` are performed.
  """
  @spec handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  def handle_event(pad_ref, event, state) do
    pad_data = PadModel.get_data!(state, pad_ref)

    if not Event.async?(event) && pad_data.mode == :pull && pad_data.direction == :input &&
         pad_data.buffer |> InputBuffer.empty?() |> Kernel.not() do
      state |> PadModel.update_data(pad_ref, :buffer, &(&1 |> InputBuffer.store(:event, event)))
    else
      exec_handle_event(pad_ref, event, state)
    end
  end

  @spec exec_handle_event(Pad.ref_t(), Event.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  def exec_handle_event(pad_ref, event, params \\ %{}, state) do
    withl handle: {{:ok, :handle}, state} <- handle_special_event(pad_ref, event, state),
          do: {:ok, state} <- check_sync(event, state),
          do: {:ok, state} <- do_exec_handle_event(pad_ref, event, params, state) do
      {:ok, state}
    else
      handle: {{:ok, :ignore}, state} ->
        debug("ignoring event #{inspect(event)}", state)
        {:ok, state}

      handle: {{:error, reason}, state} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)

      do: {:error, reason} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)
    end
  end

  @spec do_exec_handle_event(Pad.ref_t(), Event.t(), params :: map, State.t()) ::
          State.stateful_try_t()
  defp do_exec_handle_event(pad_ref, event, params, state) do
    data = PadModel.get_data!(state, pad_ref)
    context = &CallbackContext.Event.from_state/1

    CallbackHandler.exec_and_handle_callback(
      :handle_event,
      ActionHandler,
      %{context: context, direction: data.direction} |> Map.merge(params),
      [pad_ref, event],
      state
    )
  end

  defp check_sync(%Event.StartOfStream{}, state) do
    if state.pads.data
       |> Map.values()
       |> Enum.filter(&(&1.direction == :input))
       |> Enum.all?(& &1.start_of_stream?) do
      :ok = Sync.sync(state.stream_sync)
    end

    {:ok, state}
  end

  defp check_sync(_event, state) do
    {:ok, state}
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
end
