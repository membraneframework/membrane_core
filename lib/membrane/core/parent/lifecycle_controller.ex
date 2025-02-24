defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.{Child, ChildNotification, Core, Pad, Sync}

  alias Membrane.Core.{
    CallbackHandler,
    Component,
    Message,
    Parent,
    TimerController
  }

  alias Membrane.Core.Events
  alias Membrane.Core.Parent.ChildLifeController

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger

  @spec handle_setup(Parent.state()) :: Parent.state()
  def handle_setup(state) do
    Membrane.Logger.debug("Setup")

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_setup,
        Component.action_handler(state),
        %{context: &Component.context_from_state/1},
        [],
        state
      )

    with %{setup_incomplete_returned?: false} <- state do
      Membrane.Core.LifecycleController.complete_setup(state)
    end
  end

  @spec handle_playing(Parent.state()) :: Parent.state()
  def handle_playing(state) do
    Membrane.Logger.debug("Parent play")

    activate_syncs(state.children)

    pinged_children =
      state.children
      |> Enum.flat_map(fn
        {child_name, %{ready?: true, terminating?: false, pid: pid}} ->
          Message.send(pid, :play)
          [child_name]

        _other_entry ->
          []
      end)

    state = %{state | playback: :playing}

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_playing,
        Component.action_handler(state),
        %{context: &Component.context_from_state/1},
        [],
        state
      )

    ChildLifeController.handle_children_playing(pinged_children, state)
  end

  @spec handle_terminate_request(Parent.state()) :: Parent.state()
  def handle_terminate_request(%{terminating?: true} = state) do
    state
  end

  def handle_terminate_request(state) do
    state = %{state | terminating?: true}

    CallbackHandler.exec_and_handle_callback(
      :handle_terminate_request,
      Component.action_handler(state),
      %{context: &Component.context_from_state/1},
      [],
      state
    )
  end

  @spec handle_terminate(Parent.state()) :: {:continue | :stop, Parent.state()}
  def handle_terminate(state) do
    state = %{state | terminating?: true}

    if Enum.empty?(state.children) do
      {:stop, state}
    else
      state =
        state.children
        |> Map.values()
        |> Enum.reject(& &1.terminating?)
        |> Enum.map(& &1.name)
        |> ChildLifeController.handle_remove_children(state)
        |> TimerController.stop_all_timers()

      zombie_module =
        case state do
          %Core.Pipeline.State{} -> Core.Pipeline.Zombie
          %Core.Bin.State{} -> Core.Bin.Zombie
        end

      state = %{state | module: zombie_module, internal_state: %{original_module: state.module}}
      {:continue, state}
    end
  end

  @spec handle_child_notification(Child.name(), ChildNotification.t(), Parent.state()) ::
          Parent.state()
  def handle_child_notification(from, notification, state) do
    Membrane.Logger.debug_verbose(
      "Received notification #{inspect(notification)} from #{inspect(from)}"
    )

    Parent.ChildrenModel.assert_child_exists!(state, from)

    CallbackHandler.exec_and_handle_callback(
      :handle_child_notification,
      Component.action_handler(state),
      %{context: &Component.context_from_state/1},
      [notification, from],
      state
    )
  end

  @spec handle_info(any, Parent.state()) :: Parent.state()
  def handle_info(message, state) do
    CallbackHandler.exec_and_handle_callback(
      :handle_info,
      Component.action_handler(state),
      %{context: &Component.context_from_state/1},
      [message],
      state
    )
  end

  @spec handle_stream_management_event(
          Membrane.Event.t(),
          Child.name(),
          Pad.ref(),
          [start_of_stream_received?: boolean()],
          Parent.state()
        ) :: Parent.state()
  def handle_stream_management_event(%event_type{}, element_name, pad_ref, event_params, state)
      when event_type in [Events.StartOfStream, Events.EndOfStream] do
    callback =
      case event_type do
        Events.StartOfStream -> :handle_element_start_of_stream
        Events.EndOfStream -> :handle_element_end_of_stream
      end

    CallbackHandler.exec_and_handle_callback(
      callback,
      Component.action_handler(state),
      %{context: &Component.context_from_state(&1, event_params)},
      [element_name, pad_ref],
      state
    )
  end

  defp activate_syncs(children) do
    children
    |> Map.values()
    |> Enum.map(& &1.sync)
    |> Enum.uniq()
    |> Enum.each(fn sync -> :ok = Sync.activate(sync) end)
  end
end
