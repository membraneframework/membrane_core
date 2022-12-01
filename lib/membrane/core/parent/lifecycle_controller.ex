defmodule Membrane.Core.Parent.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.{Child, ChildNotification, Core, Pad, Sync}
  alias Membrane.Core.{CallbackHandler, Component, Message, Parent, TimerController}

  alias Membrane.Core.Events
  alias Membrane.Core.Parent.{ChildLifeController}

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger

  @spec handle_setup(Parent.state_t()) :: Parent.state_t()
  def handle_setup(state) do
    Membrane.Logger.debug("Setup")
    context = Component.callback_context_generator(:parent, Setup, state)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_setup,
        Component.action_handler(state),
        %{context: context},
        [],
        state
      )

    state = %{state | initialized?: true}

    case state do
      %Core.Pipeline.State{playing_requested?: true} ->
        handle_playing(state)

      %Core.Bin.State{} ->
        Message.send(state.parent_pid, :initialized, state.name)
        state

      state ->
        state
    end
  end

  @spec handle_playing(Parent.state_t()) :: Parent.state_t()
  def handle_playing(state) do
    Membrane.Logger.debug("Parent play")

    if state.__struct__ == Membrane.Core.Bin.State do
      Core.Child.PadController.assert_all_static_pads_linked!(state)
    end

    activate_syncs(state.children)

    Enum.each(state.children, fn {_name, %{pid: pid, ready?: ready?}} ->
      if ready?, do: Message.send(pid, :play)
    end)

    state = %{state | playback: :playing}
    context = Component.callback_context_generator(:parent, Playing, state)

    CallbackHandler.exec_and_handle_callback(
      :handle_playing,
      Component.action_handler(state),
      %{context: context},
      [],
      state
    )
  end

  @spec handle_terminate_request(Parent.state_t()) :: Parent.state_t()
  def handle_terminate_request(%{terminating?: true} = state) do
    state
  end

  def handle_terminate_request(state) do
    state = %{state | terminating?: true}
    context = Component.callback_context_generator(:parent, TerminateRequest, state)

    CallbackHandler.exec_and_handle_callback(
      :handle_terminate_request,
      Component.action_handler(state),
      %{context: context},
      [],
      state
    )
  end

  @spec handle_terminate(Parent.state_t()) :: {:continue | :stop, Parent.state_t()}
  def handle_terminate(state) do
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

  @spec handle_child_notification(Child.name_t(), ChildNotification.t(), Parent.state_t()) ::
          Parent.state_t()
  def handle_child_notification(from, notification, state) do
    Membrane.Logger.debug_verbose(
      "Received notification #{inspect(notification)} from #{inspect(from)}"
    )

    Parent.ChildrenModel.assert_child_exists!(state, from)
    context = Component.callback_context_generator(:parent, ChildNotification, state)

    CallbackHandler.exec_and_handle_callback(
      :handle_child_notification,
      Component.action_handler(state),
      %{context: context},
      [notification, from],
      state
    )
  end

  @spec handle_info(any, Parent.state_t()) :: Parent.state_t()
  def handle_info(message, state) do
    context = Component.callback_context_generator(:parent, Info, state)

    CallbackHandler.exec_and_handle_callback(
      :handle_info,
      Component.action_handler(state),
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

    callback =
      case event_type do
        Events.StartOfStream -> :handle_element_start_of_stream
        Events.EndOfStream -> :handle_element_end_of_stream
      end

    CallbackHandler.exec_and_handle_callback(
      callback,
      Component.action_handler(state),
      %{context: context},
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
