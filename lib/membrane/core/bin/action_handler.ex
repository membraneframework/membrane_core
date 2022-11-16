defmodule Membrane.Core.Bin.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler

  alias Membrane.ActionError
  alias Membrane.Core.Bin.State
  alias Membrane.Core.{Message, Parent, TimerController}

  require Membrane.Logger
  require Message

  @impl CallbackHandler
  def handle_action({name, args}, _cb, _params, %State{terminating?: true})
      when name in [:spec, :playback] do
    raise Membrane.ParentError,
          "Action #{inspect({name, args})} cannot be handled because the bin is already terminating"
  end

  @impl CallbackHandler
  def handle_action({:notify_child, notification}, _cb, _params, state) do
    Parent.ChildLifeController.handle_notify_child(notification, state)
    state
  end

  @impl CallbackHandler
  def handle_action({:spec, spec}, _cb, _params, state) do
    Parent.ChildLifeController.handle_spec(spec, state)
  end

  @impl CallbackHandler
  def handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_children(children, state)
  end

  @impl CallbackHandler
  def handle_action(
        {:notify_parent, notification},
        _cb,
        _params,
        %State{parent_pid: parent_pid, name: name} = state
      ) do
    Membrane.Logger.debug_verbose(
      "Sending notification #{inspect(notification)} to parent (parent PID: #{inspect(parent_pid)})"
    )

    Message.send(parent_pid, :child_notification, [name, notification])
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
  def handle_action({:terminate, :normal}, _cb, _params, %State{terminating?: false}) do
    raise Membrane.BinError,
          "Cannot terminate a bin with reason `:normal` unless it's removed by its parent"
  end

  @impl CallbackHandler
  def handle_action({:terminate, :normal}, _cb, _params, state) do
    case Parent.LifecycleController.handle_terminate(state) do
      {:continue, state} -> state
      {:stop, _state} -> exit(:normal)
    end
  end

  @impl CallbackHandler
  def handle_action({:terminate, reason}, _cb, _params, _state) do
    exit(reason)
  end

  @impl CallbackHandler
  def handle_action(action, _callback, _params, _state) do
    raise ActionError, action: action, reason: {:unknown_action, Membrane.Bin.Action}
  end
end
