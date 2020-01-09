defmodule Membrane.Core.Parent.MessageDispatcher do
  @moduledoc false

  alias Membrane.Core.Message
  alias Membrane.Core.{Parent, Pipeline, Bin}
  alias Parent.LifecycleController

  require Message

  import Membrane.Helper.GenServer

  @type state :: Pipeline.State.t() | Bin.State.t()

  @spec handle_message(Message.t(), state) ::
          Membrane.Helper.GenServer.genserver_return_t() | {:stop, reason :: :normal, state}
  def handle_message(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state
      ) do
    LifecycleController.child_playback_changed(pid, new_playback_state, state)
    |> noreply(state)
  end

  def handle_message(Message.new(:change_playback_state, new_state), state) do
    LifecycleController.change_playback_state(new_state, state)
    |> noreply(state)
  end

  def handle_message(Message.new(:stop_and_terminate), state) do
    case LifecycleController.handle_stop_and_terminate(state) do
      {{:ok, :stop}, state} ->
        {:stop, :normal, state}

      result ->
        result |> noreply(state)
    end
  end

  def handle_message(Message.new(:notification, [from, notification]), state) do
    LifecycleController.handle_notification(from, notification, state)
    |> noreply(state)
  end

  def handle_message(Message.new(:shutdown_ready, child), state) do
    LifecycleController.handle_shutdown_ready(child, state)
    |> noreply(state)
  end

  def handle_message(Message.new(cb, [element_name, pad_ref]), state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    LifecycleController.handle_stream_management_event(cb, element_name, pad_ref, state)
    |> noreply(state)
  end

  def handle_message(message, state) do
    LifecycleController.handle_other(message, state)
    |> noreply(state)
  end
end
