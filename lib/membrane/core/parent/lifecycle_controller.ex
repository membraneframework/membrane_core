defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch
  use Membrane.Core.PlaybackHandler

  alias Membrane.{Core, Sync}

  alias Core.{
    Parent,
    PadModel,
    Playback,
    PlaybackHandler,
    CallbackHandler,
    Message
  }

  alias Parent.ChildrenController

  require Message
  require PadModel
  require Membrane.PlaybackState

  @impl PlaybackHandler
  def handle_playback_state(old, new, state) do
    children_data =
      state
      |> Core.Parent.ChildrenModel.get_children()
      |> Map.values()

    children_pids = children_data |> Enum.map(& &1.pid)

    children_pids
    |> Enum.each(&Parent.change_playback_state(&1, new))

    :ok = toggle_syncs_active(old, new, children_data)

    state = %{state | pending_pids: children_pids |> MapSet.new()}

    if children_pids |> Enum.empty?() do
      {:ok, state}
    else
      PlaybackHandler.suspend_playback_change(state)
    end
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(old, new, state) do
    callback = PlaybackHandler.state_change_callback(old, new)

    if new == :stopped and state.terminating? do
      Message.self(:stop_and_terminate)
    end

    CallbackHandler.exec_and_handle_callback(callback, state.handlers.action_handler, [], state)
  end

  def handle_spec(spec, state) do
    with {{:ok, _children}, state} <-
           ChildrenController.handle_spec(spec, state) do
      {:ok, state}
    end
  end

  def change_playback_state(new_state, state) do
    PlaybackHandler.change_playback_state(new_state, __MODULE__, state)
  end

  def handle_stop(state) do
    case state.playback.state do
      :stopped ->
        {:stop, :normal, state}

      _ ->
        state = %{state | terminating?: true}

        PlaybackHandler.change_and_lock_playback_state(
          :stopped,
          state.handlers.playback_controller,
          state
        )
    end
  end

  def handle_notification(from, notification, state) do
    with {:ok, _} <- state |> Parent.ChildrenModel.get_child_data(from) do
      CallbackHandler.exec_and_handle_callback(
        :handle_notification,
        state.handlers.action_handler,
        [notification, from],
        state
      )
    else
      error ->
        {error, state}
    end
  end

  def handle_shutdown_ready(child, state) do
    {{:ok, %{pid: pid}}, state} = Parent.ChildrenModel.pop_child(state, child)
    {Core.Element.shutdown(pid), state}
  end

  def handle_demand_unit(demand_unit, pad_ref, state, _) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
  end

  def handle_other(message, state) do
    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      state.handlers.action_handler,
      [message],
      state
    )
  end

  # TODO get pending pids via child_controller?
  def child_playback_changed(
        _pid,
        _new_playback_state,
        %{pending_pids: pending_pids} = state
      )
      when pending_pids == %MapSet{} do
    {:ok, state}
  end

  def child_playback_changed(
        _pid,
        new_playback_state,
        %{playback: %Playback{pending_state: pending_playback_state}} = state
      )
      when new_playback_state != pending_playback_state do
    {:ok, state}
  end

  def child_playback_changed(pid, _new_playback_state, %{pending_pids: pending_pids} = state) do
    new_pending_pids = pending_pids |> MapSet.delete(pid)
    new_state = %{state | pending_pids: new_pending_pids}

    if new_pending_pids != pending_pids and new_pending_pids |> Enum.empty?() do
      PlaybackHandler.continue_playback_change(__MODULE__, new_state)
    else
      {:ok, new_state}
    end
  end

  def handle_stream_management_event(cb, element_name, pad_ref, state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    CallbackHandler.exec_and_handle_callback(
      to_parent_sm_callback(cb),
      state.handlers.action_handler,
      [{element_name, pad_ref}],
      state
    )
  end

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
