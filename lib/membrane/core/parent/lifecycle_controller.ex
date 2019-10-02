defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch
  use Membrane.Core.PlaybackHandler

  alias Membrane.Element

  alias Membrane.Core.{
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

  @type handlers :: %{
          action_handler: module(),
          playback_controller: module(),
          spec_controller: module()
        }

  def handle_playback_state_changed(
        _pid,
        _new_playback_state,
        %{pending_pids: pending_pids} = state,
        _handlers
      )
      when pending_pids == %MapSet{} do
    {:ok, state}
  end

  def handle_playback_state_changed(
        _pid,
        new_playback_state,
        %{playback: %Playback{pending_state: pending_playback_state}} = state,
        _handlers
      )
      when new_playback_state != pending_playback_state do
    {:ok, state}
  end

  def handle_playback_state_changed(pid, new_playback_state, state, handlers) do
    %{playback: %Playback{state: current_playback_state}, pending_pids: pending_pids} = state
    new_pending_pids = pending_pids |> MapSet.delete(pid)
    new_state = %{state | pending_pids: new_pending_pids}

    if new_pending_pids != pending_pids and new_pending_pids |> Enum.empty?() do

      PlaybackHandler.continue_playback_change(handlers.playback_controller, new_state)
    else
      {:ok, new_state}
    end
  end

  def handle_spec(spec, state, handlers) do
    with {{:ok, _children}, state} <-
           handlers.spec_controller |> ChildrenController.handle_spec(spec, state) do
      {:ok, state}
    end
  end

  def change_playback_state(new_state, state, _handlers) do
    PlaybackHandler.change_playback_state(new_state, __MODULE__, state)
  end

  def handle_stop(state, handlers) do
    case state.playback.state do
      :stopped ->
        {:stop, :normal, state}

      _ ->
        state = %{state | terminating?: true}

        PlaybackHandler.change_and_lock_playback_state(
          :stopped,
          handlers.playback_controller,
          state
        )
    end
  end

  def handle_notification(from, notification, state, handlers) do
    with {:ok, _} <- state |> Parent.ChildrenModel.get_child_data(from) do
      CallbackHandler.exec_and_handle_callback(
        :handle_notification,
        handlers.action_handler,
        [notification, from],
        state
      )
    else
      error ->
        {error, state}
    end
  end

  def handle_shutdown_ready(child, state, _handlers) do
    {{:ok, %{pid: pid}}, state} = Parent.ChildrenModel.pop_child(state, child)
    {Element.shutdown(pid), state}
  end

  def handle_demand_unit(demand_unit, pad_ref, state, _) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
  end

  def handle_other(message, state, handlers) do
    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      handlers.action_handler,
      [message],
      state
    )
  end

  @impl PlaybackHandler
  def handle_playback_state(_old, new, state) do
    children_pids = state |> Parent.ChildrenModel.get_children() |> Map.values()

    children_pids
    |> Enum.each(fn pid ->
      change_playback_state(pid, new)
    end)

    state = %{state | pending_pids: children_pids |> MapSet.new()}
    PlaybackHandler.suspend_playback_change(state)
  end

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  defp change_playback_state(pid, new_state)
       when Membrane.PlaybackState.is_playback_state(new_state) do
    alias Membrane.Core.Message
    require Message
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end

  def handle_stream_management_event(cb, element_name, pad_ref, state, handlers)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    CallbackHandler.exec_and_handle_callback(
      to_parent_sm_callback(cb),
      handlers.action_handler,
      [{element_name, pad_ref}],
      state
    )
  end

  defp to_parent_sm_callback(:handle_start_of_stream), do: :handle_element_start_of_stream
  defp to_parent_sm_callback(:handle_end_of_stream), do: :handle_element_end_of_stream
end
