defmodule Membrane.Core.Parent.MessageDispatcher do
  @moduledoc false
  alias Membrane.Core.Message

  alias Membrane.Core.{Parent, Pipeline, Bin}
  alias Parent.LifecycleController
  alias Bunch.Type

  require Message

  @type handlers :: %{
          action_handler: module(),
          playback_controller: module(),
          spec_controller: module()
        }

  @spec handle_message(Message.t(), Pipeline.State.t() | Bin.State.t()) ::
          Type.stateful_try_t(any)
  def handle_message(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state
      ) do
    LifecycleController.child_playback_changed(pid, new_playback_state, state)
  end

  def handle_message(Message.new(:change_playback_state, new_state), state) do
    LifecycleController.change_playback_state(new_state, state)
  end

  def handle_message(Message.new(:stop_and_terminate), state) do
    LifecycleController.handle_stop_and_terminate(state)
  end

  def handle_message(Message.new(:notification, [from, notification]), state) do
    LifecycleController.handle_notification(from, notification, state)
  end

  def handle_message(Message.new(:shutdown_ready, child), state) do
    LifecycleController.handle_shutdown_ready(child, state)
  end

  def handle_message(Message.new(cb, [element_name, pad_ref]), state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    LifecycleController.handle_stream_management_event(cb, element_name, pad_ref, state)
  end

  def handle_message(message, state) do
    LifecycleController.handle_other(message, state)
  end
end
