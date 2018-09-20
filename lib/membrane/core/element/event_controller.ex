defmodule Membrane.Core.Element.EventController do
  @moduledoc false
  # Module handling events infoming through input pads.

  alias Membrane.{Core, Element, Event}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{ActionHandler, PadModel, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.Event
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles incoming event: either stores it in PullBuffer, or executes element callback.
  Extra checks and tasks required by special events such as `:sos` or `:eos`
  are performed.
  """
  @spec handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  def handle_event(pad_ref, event, state) do
    pad_data = PadModel.get_data!(pad_ref, state)

    if event.mode == :sync && pad_data.mode == :pull && pad_data.direction == :input &&
         pad_data.buffer |> PullBuffer.empty?() |> Kernel.not() do
      PadModel.update_data(
        pad_ref,
        :buffer,
        &(&1 |> PullBuffer.store(:event, event)),
        state
      )
    else
      exec_handle_event(pad_ref, event, state)
    end
  end

  @spec exec_handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  def exec_handle_event(pad_ref, event, state) do
    withl handle: {{:ok, :handle}, state} <- handle_special_event(pad_ref, event, state),
          exec: {:ok, state} <- do_exec_handle_event(pad_ref, event, state) do
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

  @spec do_exec_handle_event(Pad.ref_t(), Event.t(), State.t()) :: State.stateful_try_t()
  defp do_exec_handle_event(pad_ref, event, state) do
    data = PadModel.get_data!(pad_ref, state)
    context = CallbackContext.Event.from_state(state, caps: data.caps)

    CallbackHandler.exec_and_handle_callback(
      :handle_event,
      ActionHandler,
      %{direction: data.direction},
      [pad_ref, event, context],
      state
    )
  end

  @spec handle_special_event(Pad.ref_t(), Event.t(), State.t()) ::
          State.stateful_try_t(:handle | :ignore)
  defp handle_special_event(pad_ref, %Event{type: :sos}, state) do
    with %{direction: :input, sos: false} <- PadModel.get_data!(pad_ref, state) do
      state = PadModel.set_data!(pad_ref, :sos, true, state)
      {{:ok, :handle}, state}
    else
      %{direction: :output} -> {{:error, {:received_sos_through_output, pad_ref}}, state}
      %{sos: true} -> {{:error, {:sos_already_received, pad_ref}}, state}
    end
  end

  defp handle_special_event(pad_ref, %Event{type: :eos}, state) do
    with %{direction: :input, sos: true, eos: false} <- PadModel.get_data!(pad_ref, state) do
      state = PadModel.set_data!(pad_ref, :eos, true, state)
      {{:ok, :handle}, state}
    else
      %{direction: :output} -> {{:error, {:received_eos_through_output, pad_ref}}, state}
      %{eos: true} -> {{:error, {:eos_already_received, pad_ref}}, state}
      %{sos: false} -> {{:ok, :ignore}, state}
    end
  end

  # FIXME: solve it using pipeline messages, not events
  defp handle_special_event(_pad_ref, %Event{type: :dump_state}, state) do
    IO.puts("""
    state dump for #{inspect(state.name)} at #{inspect(self())}
    state:
    #{inspect(state)}
    info:
    #{inspect(:erlang.process_info(self()))}
    """)

    {{:ok, :handle}, state}
  end

  defp handle_special_event(_pad_ref, _event, state), do: {{:ok, :handle}, state}
end
