defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch
  use Membrane.Core.PlaybackHandler

  alias Membrane.{Child, ChildNotification, Core, Pad, Sync}
  alias Membrane.Core.{CallbackHandler, Component, Message, Parent, PlaybackHandler}

  alias Membrane.Core.Events
  alias Membrane.Core.Parent.ChildrenModel
  alias Membrane.PlaybackState

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger
  require Membrane.PlaybackState

  def handle_setup(state) do
    context = Component.callback_context_generator(:parent, PlaybackChange, state)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_stopped_to_prepared,
        Component.action_handler(state),
        %{context: context},
        [],
        state
      )

    state = put_in(state, [:playback, :state], :prepared)
    state = %{state | status: :initialized}

    case state do
      %Core.Pipeline.State{play_request?: true} -> handle_play(state)
      state -> state
    end
  end

  def handle_play(state) do
    Enum.each(state.children, fn {_name, %{pid: pid, status: status}} ->
      if status == :ready, do: Message.send(pid, :play)
    end)

    context = Component.callback_context_generator(:parent, PlaybackChange, state)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_prepared_to_playing,
        Component.action_handler(state),
        %{context: context},
        [],
        state
      )

    state = put_in(state, [:playback, :state], :playing)
    %{state | status: :playing}
  end

  @impl PlaybackHandler
  def handle_playback_state(old, new, state) do
    Membrane.Logger.debug("Changing playback state from #{old} to #{new}")
    children_data = Map.values(state.children)
    :ok = toggle_syncs_active(old, new, children_data)

    children_data
    |> Enum.reject(&(&1.playback_sync == :not_synced))
    |> Enum.each(&PlaybackHandler.request_playback_state_change(&1.pid, new))

    state =
      ChildrenModel.update_children(
        state,
        &if(&1.playback_sync == :synced, do: %{&1 | playback_sync: :syncing}, else: &1)
      )

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

    state =
      if callback do
        CallbackHandler.exec_and_handle_callback(
          callback,
          action_handler,
          %{context: context},
          [],
          state
        )
      else
        state
      end

    if state.__struct__ == Membrane.Core.Bin.State do
      case {old, new} do
        {:stopped, :prepared} -> Core.Child.PadController.assert_all_static_pads_linked!(state)
        _other -> :ok
      end
    end

    Membrane.Logger.debug("Playback state changed from #{old} to #{new}")

    if new == :terminating do
      Process.flag(:trap_exit, false)
      Process.exit(self(), :normal)
    end

    {:ok, state}
  end

  @spec change_playback_state(PlaybackState.t(), Parent.state_t()) :: Parent.state_t()
  def change_playback_state(new_playback_state, state) do
    if Enum.empty?(state.pending_specs) do
      {:ok, state} = PlaybackHandler.change_playback_state(new_playback_state, __MODULE__, state)
      state
    else
      %{state | delayed_playback_change: new_playback_state}
    end
  end

  @spec handle_child_notification(Child.name_t(), ChildNotification.t(), Parent.state_t()) ::
          Parent.state_t()
  def handle_child_notification(from, notification, state) do
    Membrane.Logger.debug_verbose(
      "Received notification #{inspect(notification)} from #{inspect(from)}"
    )

    Parent.ChildrenModel.assert_child_exists!(state, from)
    context = Component.callback_context_generator(:parent, ChildNotification, state)
    action_handler = get_callback_action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_child_notification,
      action_handler,
      %{context: context},
      [notification, from],
      state
    )
  end

  @spec handle_info(any, Parent.state_t()) :: Parent.state_t()
  def handle_info(message, state) do
    context = Component.callback_context_generator(:parent, Other, state)
    action_handler = get_callback_action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_info,
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
        ) :: Parent.state_t()
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
      [element_name, pad_ref],
      state
    )
  end

  @spec maybe_finish_playback_transition(Parent.state_t()) :: Parent.state_t()
  def maybe_finish_playback_transition(state) do
    all_children_in_sync? = ChildrenModel.all?(state, &(&1.playback_sync == :synced))

    if PlaybackHandler.suspended?(state) and all_children_in_sync? do
      {:ok, state} = PlaybackHandler.continue_playback_change(__MODULE__, state)
      state
    else
      state
    end
  end

  defp get_callback_action_handler(%Core.Pipeline.State{}), do: Core.Pipeline.ActionHandler
  defp get_callback_action_handler(%Core.Bin.State{}), do: Core.Bin.ActionHandler

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
