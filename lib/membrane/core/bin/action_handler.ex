defmodule Membrane.Core.Bin.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler

  alias Membrane.Core.{Message, Parent, TimerController}
  alias Membrane.Core.Bin.State
  alias Membrane.{CallbackError, Notification, ParentSpec}

  require Membrane.Logger
  require Message

  @impl CallbackHandler
  def handle_action({:forward, children_messages}, _cb, _params, state) do
    Parent.ChildLifeController.handle_forward(Bunch.listify(children_messages), state)
  end

  @impl CallbackHandler
  def handle_action({:spec, spec = %ParentSpec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- Parent.ChildLifeController.handle_spec(spec, state),
         do: {:ok, state}
  end

  @impl CallbackHandler
  def handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_child(children, state)
  end

  @impl CallbackHandler
  def handle_action({:remove_link, links}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_link(links, state)
  end

  @impl CallbackHandler
  def handle_action({:notify, notification}, _cb, _params, state) do
    send_notification(notification, state)
  end

  @impl CallbackHandler
  def handle_action({:log_metadata, metadata}, _cb, _params, state) do
    Parent.LifecycleController.handle_log_metadata(metadata, state)
  end

  @impl CallbackHandler
  def handle_action({:start_timer, {id, interval, clock}}, _cb, _params, state) do
    TimerController.start_timer(id, interval, clock, state)
  end

  @impl CallbackHandler
  def handle_action({:start_timer, {id, interval}}, cb, params, state) do
    clock = state.synchronization.clock_proxy
    handle_action({:start_timer, {id, interval, clock}}, cb, params, state)
  end

  @impl CallbackHandler
  def handle_action({:timer_interval, {id, interval}}, cb, _params, state)
      when interval != :no_interval or cb == :handle_tick do
    TimerController.timer_interval(id, interval, state)
  end

  @impl CallbackHandler
  def handle_action({:stop_timer, id}, _cb, _params, state) do
    TimerController.stop_timer(id, state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, _params, state) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {state.module, callback}
  end

  @spec send_notification(Notification.t(), State.t()) :: {:ok, State.t()}
  defp send_notification(notification, %State{parent_pid: parent_pid, name: name} = state) do
    Membrane.Logger.debug(
      "Sending notification #{inspect(notification)} (parent PID: #{inspect(parent_pid)})"
    )

    Message.send(parent_pid, :notification, [name, notification])
    {:ok, state}
  end
end
