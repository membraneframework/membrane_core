defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch
  use Membrane.Core.PlaybackHandler

  require Membrane.Core.Message
  require Membrane.Core.Parent
  require Membrane.Logger
  require Membrane.PlaybackState

  alias Bunch.Type
  alias Membrane.{Child, Core, Notification, Pad, Sync}

  alias Membrane.Core.{
    Parent,
    PlaybackHandler,
    CallbackHandler,
    Message
  }

  alias Membrane.Core.Parent.ChildrenModel
  alias Membrane.PlaybackState

  @type state_t :: Core.Bin.State.t() | Core.Pipeline.State.t()

  @impl PlaybackHandler
  def handle_playback_state(old, new, state) do
    Membrane.Logger.debug("Changing playback state from #{old} to #{new}")

    children_data =
      state
      |> ChildrenModel.get_children()
      |> Map.values()

    children_pids = children_data |> Enum.map(& &1.pid)

    children_pids
    |> Enum.each(&PlaybackHandler.request_playback_state_change(&1, new))

    :ok = toggle_syncs_active(old, new, children_data)

    state = state |> ChildrenModel.update_children(&%{&1 | pending?: true})

    if children_pids |> Enum.empty?() do
      {:ok, state}
    else
      PlaybackHandler.suspend_playback_change(state)
    end
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(old, new, state) do
    context = Parent.callback_context_generator(PlaybackChange, state)
    callback = PlaybackHandler.state_change_callback(old, new)
    action_handler = get_callback_action_handler(state)

    callback_res =
      if callback do
        CallbackHandler.exec_and_handle_callback(
          callback,
          action_handler,
          %{context: context},
          [],
          state
        )
      else
        {:ok, state}
      end

    with {:ok, state} <- callback_res do
      case state do
        %Core.Pipeline.State{} ->
          Membrane.Logger.info("Pipeline playback state changed from #{old} to #{new}")

        %Core.Bin.State{} ->
          Membrane.Logger.debug("Playback state changed from #{old} to #{new}")
      end

      if new == :terminating,
        do: {:stop, :normal, state},
        else: callback_res
    end
  end

  @spec change_playback_state(PlaybackState.t(), Parent.State.t()) ::
          PlaybackHandler.handler_return_t()
  def change_playback_state(new_state, state) do
    PlaybackHandler.change_playback_state(new_state, __MODULE__, state)
  end

  @spec handle_notification(Child.name_t(), Notification.t(), state_t) ::
          Type.stateful_try_t(state_t)
  def handle_notification(from, notification, state) do
    with {:ok, _} <- state |> Parent.ChildrenModel.get_child_data(from) do
      context = Parent.callback_context_generator(Notification, state)
      action_handler = get_callback_action_handler(state)

      CallbackHandler.exec_and_handle_callback(
        :handle_notification,
        action_handler,
        %{context: context},
        [notification, from],
        state
      )
    else
      error ->
        {error, state}
    end
  end

  @spec handle_other(any, state_t()) :: Type.stateful_try_t(state_t)
  def handle_other(message, state) do
    context = Parent.callback_context_generator(Other, state)
    action_handler = get_callback_action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      action_handler,
      %{context: context},
      [message],
      state
    )
  end

  @spec child_playback_changed(pid, PlaybackState.t(), state_t()) ::
          PlaybackHandler.handler_return_t()
  def child_playback_changed(pid, new_pb_state, state) do
    if transition_finished?(new_pb_state, state.playback.pending_state) do
      finish_pids_transition(state, pid)
    else
      {:ok, state}
    end
  end

  defp no_child_in_transition?(state),
    do: ChildrenModel.all?(state, &(not &1.pending?))

  defp transition_finished?(pending_state, new_state)
  defp transition_finished?(pb_state, pb_state), do: true
  defp transition_finished?(_, _), do: false

  # Child was removed
  def handle_child_death(pid, :normal, state) do
    {:ok, state} = finish_pids_transition(state, pid)

    new_children =
      state
      |> ChildrenModel.get_children()
      |> Enum.filter(fn {_name, entry} -> entry.pid != pid end)
      |> Enum.into(%{})

    {:ok, %{state | children: new_children}}
  end

  defp finish_pids_transition(state, pid) do
    state =
      state
      |> ChildrenModel.update_children(fn
        %{pid: ^pid} = child -> %{child | pending?: false}
        child -> child
      end)

    # If we suspended playback state change and there are no pending children
    # this means we want to continue the change for the parent.
    if PlaybackHandler.suspended?(state) and no_child_in_transition?(state) do
      PlaybackHandler.continue_playback_change(__MODULE__, state)
    else
      {:ok, state}
    end
  end

  @spec handle_stream_management_event(atom, Child.name_t(), Pad.ref_t(), state_t()) ::
          Type.stateful_try_t(state_t)
  def handle_stream_management_event(cb, element_name, pad_ref, state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    context = Parent.callback_context_generator(StreamManagement, state)
    action_handler = get_callback_action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      to_parent_sm_callback(cb),
      action_handler,
      %{context: context},
      [{element_name, pad_ref}],
      state
    )
  end

  @spec handle_log_metadata(Keyword.t(), state_t) :: {:ok, state_t()}
  def handle_log_metadata(metadata, state) do
    :ok = Logger.metadata(metadata)

    children_log_metadata =
      state.children_log_metadata
      |> Map.new()
      |> Map.merge(Map.new(metadata))
      |> Bunch.KVEnum.filter_by_values(&(&1 != nil))

    Bunch.KVEnum.each_value(state.children, &Message.send(&1.pid, :log_metadata, metadata))

    {:ok, %{state | children_log_metadata: children_log_metadata}}
  end

  defp get_callback_action_handler(%Core.Pipeline.State{}), do: Core.Pipeline.ActionHandler
  defp get_callback_action_handler(%Core.Bin.State{}), do: Core.Bin.ActionHandler

  defp to_parent_sm_callback(:handle_start_of_stream), do: :handle_element_start_of_stream
  defp to_parent_sm_callback(:handle_end_of_stream), do: :handle_element_end_of_stream

  defp toggle_syncs_active(:prepared, :playing, children_data) do
    do_toggle_syncs_active(children_data, &Sync.activate/1)
  end

  defp toggle_syncs_active(:playing, :prepared, children_data) do
    do_toggle_syncs_active(children_data, &Sync.deactivate/1)
  end

  defp toggle_syncs_active(_old_playback_state, _new_playback_state, _children_data) do
    :ok
  end

  defp do_toggle_syncs_active(children_data, fun) do
    children_data |> Enum.uniq_by(& &1.sync) |> Enum.map(& &1.sync) |> Bunch.Enum.try_each(fun)
  end
end
