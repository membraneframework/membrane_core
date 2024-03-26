defmodule Membrane.Core.Pipeline.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler

  alias Membrane.ActionError
  alias Membrane.Core
  alias Membrane.Core.{Parent, TimerController}
  alias Membrane.Core.Parent.LifecycleController
  alias Membrane.Core.Pipeline.State

  require Membrane.Logger

  @impl CallbackHandler
  def handle_action({:spec, args}, _cb, _params, %State{terminating?: true}) do
    raise Membrane.ParentError,
          "Action #{inspect({:spec, args})} cannot be handled because the pipeline is already terminating"
  end

  @impl CallbackHandler
  def handle_action({:setup, :incomplete} = action, cb, _params, _state)
      when cb != :handle_setup do
    raise ActionError, action: action, reason: {:invalid_callback, :handle_setup}
  end

  @impl CallbackHandler
  def handle_action({:setup, operation}, _cb, _params, state) do
    Core.LifecycleController.handle_setup_operation(operation, state)
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
  def handle_action({:remove_children, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_children(children, state)
  end

  @impl CallbackHandler
  def handle_action({:remove_link, {child_name, pad_ref}}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_link(child_name, pad_ref, state)
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
  def handle_action({:reply_to, {pid, message}}, _cb, _params, state) do
    GenServer.reply(pid, message)
    state
  end

  @impl CallbackHandler
  def handle_action({:reply, message}, :handle_call, params, state) do
    ctx = params.context.(state)
    GenServer.reply(ctx.from, message)
    state
  end

  @impl CallbackHandler
  def handle_action({:reply, _message} = action, cb, _params, _state) do
    raise ActionError, action: action, reason: {:invalid_callback, cb}
  end

  @impl CallbackHandler
  def handle_action({:terminate, :normal}, _cb, _params, state) do
    case LifecycleController.handle_terminate(state) do
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
    raise ActionError, action: action, reason: {:unknown_action, Membrane.Pipeline.Action}
  end

  @impl CallbackHandler
  def handle_end_of_actions(_callback, state) do
    with %{awaiting_setup_completition?: true} <- state do
      %{state | awaiting_setup_completition?: false}
      |> Membrane.Core.LifecycleController.complete_setup()
    end
  end
end
