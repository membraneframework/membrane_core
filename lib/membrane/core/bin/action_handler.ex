defmodule Membrane.Core.Bin.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler

  alias Membrane.ActionError
  alias Membrane.Core.{Message, Parent, TimerController}
  alias Membrane.Core.Bin.State
  alias Membrane.ParentSpec

  require Membrane.Logger
  require Message

  @impl CallbackHandler
  def handle_action({:forward, children_messages}, _cb, _params, state) do
    :ok = Parent.ChildLifeController.handle_forward(Bunch.listify(children_messages), state)
    state
  end

  @impl CallbackHandler
  def handle_action({:spec, spec = %ParentSpec{}}, _cb, _params, state) do
    Parent.ChildLifeController.handle_spec(spec, state)
  end

  @impl CallbackHandler
  def handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_child(children, state)
  end

  @impl CallbackHandler
  def handle_action({:notify, notification}, _cb, _params, state) do
    %State{parent_pid: parent_pid, name: name} = state

    Membrane.Logger.debug_verbose(
      "Sending notification #{inspect(notification)} (parent PID: #{inspect(parent_pid)})"
    )

    Message.send(parent_pid, :notification, [name, notification])
    state
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
  def handle_action(action, _callback, _params, _state) do
    raise ActionError, action: action, reason: {:unknown_action, Membrane.Bin.Action}
  end
end
