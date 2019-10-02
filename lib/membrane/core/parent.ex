defmodule Membrane.Core.Parent do
  #use Membrane.Core.PlaybackHandler

  alias Membrane.{Core, Sync}
  alias Core.{CallbackHandler, Message, Playback, PlaybackHandler}

  require Membrane.PlaybackState
  require Message

  # TODO these functions should probably be simply moved to Parent.LifecycleController (?) unless used elsewhere.

  def handle_playback_state(old, new, state) do
    children_data =
      state
      |> Core.Parent.ChildrenModel.get_children()
      |> Map.values()

    children_pids = children_data |> Enum.map(& &1.pid)

    children_pids
    |> Enum.each(&change_playback_state(&1, new))

    :ok = toggle_syncs_active(old, new, children_data)

    state = %{state | pending_pids: children_pids |> MapSet.new()}

    if children_pids |> Enum.empty?() do
      {:ok, state}
    else
      PlaybackHandler.suspend_playback_change(state)
    end
  end

  def handle_playback_state_changed(old, new, state) do
    callback = PlaybackHandler.state_change_callback(old, new)

    if new == :stopped and state.terminating? do
      Message.self(:stop_and_terminate)
    end

    CallbackHandler.exec_and_handle_callback(callback, state.handlers.action_handler, [], state)
  end

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  def change_playback_state(pid, new_state)
      when Membrane.PlaybackState.is_playback_state(new_state) do
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end

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
