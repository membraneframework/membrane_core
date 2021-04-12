defmodule Membrane.Core.Parent.MessageDispatcher do
  @moduledoc false

  import Membrane.Helper.GenServer

  alias Membrane.Core.{Parent, Pipeline, TimerController}
  alias Membrane.Core.Message
  alias Membrane.Core.Parent.{ChildLifeController, LifecycleController}

  require Membrane.Core.Message
  require Membrane.Logger

  @spec handle_message(Message.t(), Parent.state_t()) ::
          Membrane.Helper.GenServer.genserver_return_t()
          | {:stop, reason :: :normal, Parent.state_t()}
  def handle_message(
        Message.new(:playback_state_changed, [pid, new_playback_state]),
        state
      ) do
    ChildLifeController.child_playback_changed(pid, new_playback_state, state)
    |> noreply(state)
  end

  def handle_message(Message.new(:change_playback_state, new_state), state) do
    LifecycleController.change_playback_state(new_state, state)
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

  def handle_message(Message.new(:log_metadata, metadata), state) do
    LifecycleController.handle_log_metadata(metadata, state)
    |> noreply(state)
  end

  def handle_message(Message.new(:timer_tick, timer_id), state) do
    TimerController.handle_tick(timer_id, state) |> noreply(state)
  end

  def handle_message({:membrane_clock_ratio, clock, ratio}, state) do
    TimerController.handle_clock_update(clock, ratio, state) |> noreply(state)
  end

  # when monitored child exited normally
  def handle_message({:DOWN, _ref, :process, pid, reason} = message, state) do
    with {{:ok, result}, state} <-
           ChildLifeController.maybe_handle_child_death(pid, reason, state) do
      case result do
        :child -> {:ok, state}
        :not_child -> LifecycleController.handle_other(message, state)
      end
    end
    |> noreply(state)
  end

  # # when child exited because other member of crash group that is belong to crashed
  # # ignoring that message
  # def handle_message({:DOWN, _ref, :process, _pid, :group_down}, state) do
  #    |> noreply()
  # end

  # # when child exited abnormally
  # def handle_message({:DOWN, _ref, :process, pid, reason}, state) do
  #   # check if child was in any crash groups
  #   crash_group =
  #     state.crash_groups
  #     |> Enum.find(fn %CrashGroup{members: members_pids} ->
  #       pid in members_pids
  #     end)

  #   if crash_group do
  #     # mode is not used for now as only temporary mode is supported
  #     %CrashGroup{name: group_name, mode: :temporary, members: members_pids} = crash_group

  #     # find all links connected with this group
  #     all_links = state.links

  #     links_to_unlink =
  #       all_links
  #       |> Enum.filter(fn %Link{from: from, to: to} ->
  #         from.pid in members_pids or to.pid in members_pids
  #       end)

  #     with {:ok, state} <- ChildLifeController.LinkHandler.unlink_children(links_to_unlink, state) do
  #       Membrane.Logger.debug("""
  #       Member of crash group #{group_name} has terminated due to #{inspect(reason)}.
  #       Terminating rest of groups members.
  #       """)

  #       members_pids |> Enum.each(&if Process.alive?(&1), do: GenServer.stop(&1, :group_down))

  #       ChildLifeController.CrashGroupHandler.remove_crash_group(group_name, state)
  #     end
  #   else
  #     Membrane.Logger.debug("""
  #     Pipeline child crashed but was not member of any crash group.
  #     Terminating.
  #     """)

  #     GenServer.stop(self(), :kill)
  #   end
  #   |> noreply(state)
  # end

  def handle_message(message, state) do
    LifecycleController.handle_other(message, state)
    |> noreply(state)
  end

  defp inform_parent(state, msg, msg_params) do
    if not pipeline?(state) and state.watcher,
      do: Message.send(state.watcher, msg, [state.name | msg_params])
  end

  defp pipeline?(%Pipeline.State{}), do: true
  defp pipeline?(_state), do: false
end
