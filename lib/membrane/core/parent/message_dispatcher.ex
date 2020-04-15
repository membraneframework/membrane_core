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

  def handle_message(Message.new(:terminate), state) do
    state
    |> LifecycleController.handle_terminate()
    |> noreply(state)
  end

  def handle_message(Message.new(:notification, [from, notification]), state) do
    LifecycleController.handle_notification(from, notification, state)
    |> noreply(state)
  end

  def handle_message(Message.new(cb, [element_name, pad_ref]), state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    inform_parent(state, cb, [pad_ref])

    LifecycleController.handle_stream_management_event(cb, element_name, pad_ref, state)
    |> noreply(state)
  end

  def handle_message({:DOWN, _ref, :process, child_pid, reason}, state) do
    LifecycleController.handle_child_death(child_pid, reason, state)
    |> noreply(state)
  end

  def handle_message(message, state) do
    LifecycleController.handle_other(message, state)
    |> noreply(state)
  end

  defp inform_parent(state, msg, msg_params) do
    if not pipeline?(state) and state.watcher,
      do: Message.send(state.watcher, msg, [state.name | msg_params])
  end

  defp pipeline?(%Pipeline.State{}), do: true
  defp pipeline?(_), do: false
end
