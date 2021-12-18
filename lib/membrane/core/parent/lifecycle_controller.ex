defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch
  use Membrane.Core.PlaybackHandler

  alias Bunch.Type
  alias Membrane.{Child, Core, Notification, Pad, Sync}
  alias Membrane.Core.{CallbackHandler, Message, Component, Parent, PlaybackHandler}
  alias Membrane.Core.Events
  alias Membrane.Core.Parent.ChildrenModel
  alias Membrane.PlaybackState

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger
  require Membrane.PlaybackState

  @impl PlaybackHandler
  def handle_playback_state(old, new, state) do
    Membrane.Logger.debug("Changing playback state from #{old} to #{new}")
    children_data = Map.values(state.children)
    :ok = toggle_syncs_active(old, new, children_data)
    Enum.each(children_data, &PlaybackHandler.request_playback_state_change(&1.pid, new))
    {:ok, state} = ChildrenModel.update_children(state, &%{&1 | playback_synced?: false})

    if children_data |> Enum.empty?() do
      {:ok, state}
    else
      PlaybackHandler.suspend_playback_change(state)
    end
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(old, new, state) do
    context = Component.callback_context_generator(:parent, PlaybackChange, state)
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

    if state.__struct__ == Membrane.Core.Bin.State and new == :stopped do
      Core.Child.LifecycleController.unlink(state)
    end

    with {:ok, state} <- callback_res do
      Membrane.Logger.debug("Playback state changed from #{old} to #{new}")

      if new == :terminating do
        {:stop, :normal, state}
      else
        {:ok, state}
      end
    end
  end

  @spec change_playback_state(PlaybackState.t(), Parent.state_t()) ::
          PlaybackHandler.handler_return_t()
  def change_playback_state(new_state, state) do
    PlaybackHandler.change_playback_state(new_state, __MODULE__, state)
  end

  @spec handle_notification(Child.name_t(), Notification.t(), Parent.state_t()) ::
          Type.stateful_try_t(Parent.state_t())
  def handle_notification(from, notification, state) do
    with {:ok, _} <- state |> Parent.ChildrenModel.get_child_data(from) do
      context = Component.callback_context_generator(:parent, Notification, state)
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

  @spec handle_other(any, Parent.state_t()) :: Type.stateful_try_t(Parent.state_t())
  def handle_other(message, state) do
    context = Component.callback_context_generator(:parent, Other, state)
    action_handler = get_callback_action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      action_handler,
      %{context: context},
      [message],
      state
    )
  end

  @spec handle_stream_management_event(
          Membrane.Event.t(),
          Child.name_t(),
          Pad.ref_t(),
          Parent.state_t()
        ) ::
          Type.stateful_try_t(Parent.state_t())
  def handle_stream_management_event(%event_type{}, element_name, pad_ref, state)
      when event_type in [Events.StartOfStream, Events.EndOfStream] do
    context = Component.callback_context_generator(:parent, StreamManagement, state)
    action_handler = get_callback_action_handler(state)

    callback =
      case event_type do
        Events.StartOfStream -> :handle_element_start_of_stream
        Events.EndOfStream -> :handle_element_end_of_stream
      end

    CallbackHandler.exec_and_handle_callback(
      callback,
      action_handler,
      %{context: context},
      [{element_name, pad_ref}],
      state
    )
  end

  @spec handle_log_metadata(Keyword.t(), Parent.state_t()) :: {:ok, Parent.state_t()}
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

  @spec maybe_finish_playback_transition(Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def maybe_finish_playback_transition(state) do
    all_children_in_sync? = ChildrenModel.all?(state, & &1.playback_synced?)

    if PlaybackHandler.suspended?(state) and all_children_in_sync? do
      PlaybackHandler.continue_playback_change(__MODULE__, state)
    else
      {:ok, state}
    end
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
