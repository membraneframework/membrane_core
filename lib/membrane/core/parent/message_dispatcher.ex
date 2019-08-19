defmodule Membrane.Core.Parent.MessageDispatcher do
  alias Membrane.Core.Message

  alias Membrane.Core.Parent.{LifecycleController, State}

  require Message

  @type handlers :: %{
          action_handler: module(),
          playback_controller: module(),
          spec_controller: module()
        }

  @spec handle_message(Message.t(), :info | :call | :other, State.t()) ::
          State.stateful_try_t(any)
  def handle_message(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state,
        handlers
      ) do
    LifecycleController.handle_playback_state_changed(pid, new_playback_state, state, handlers)
  end

  def handle_message(Message.new(:handle_spec, spec), state, handlers) do
    LifecycleController.handle_spec(spec, state, handlers)
  end

  def handle_message(Message.new(:change_playback_state, new_state), state, handlers) do
    LifecycleController.change_playback_state(new_state, state, handlers)
  end

  def handle_message(Message.new(:stop_and_terminate), state, handlers) do
    LifecycleController.handle_stop(state, handlers)
  end

  def handle_message(Message.new(:notification, [from, notification]), state, handlers) do
    LifecycleController.handle_notification(from, notification, state, handlers)
  end

  def handle_message(Message.new(:shutdown_ready, child), state, handlers) do
    LifecycleController.handle_shutdown_ready(child, state, handlers)
  end

  def handle_message(Message.new(cb, [element_name, pad_ref]), state, handlers)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    LifecycleController.handle_stream_management_event(cb, element_name, pad_ref, state, handlers)
  end

  def handle_message(message, state, handlers) do
    LifecycleController.handle_other(message, state, handlers)
  end
end
