defmodule Membrane.Core.Pipeline.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler

  alias Membrane.CallbackError
  alias Membrane.Core.{Parent, TimerController}
  alias Membrane.ParentSpec

  require Membrane.Logger

  @impl CallbackHandler
  # Deprecation
  def handle_actions(%ParentSpec{} = spec, :handle_init, params, state) do
    Membrane.Logger.warn("""
    Returning bare spec from `handle_init` is deprecated.
    Return `{{:ok, spec: spec}, state}` instead.
    Found in `#{inspect(state.module)}.handle_init/1`.
    """)

    super([spec: spec], :handle_init, params, state)
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, params, state) do
    super(actions, callback, params, state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, params, state) do
    with {:ok, state} <- do_handle_action(action, callback, params, state) do
      {:ok, state}
    else
      {{:error, :invalid_action}, state} ->
        raise CallbackError,
          kind: :invalid_action,
          action: action,
          callback: {state.module, callback}

      error ->
        error
    end
  end

  defp do_handle_action({action, _args}, :handle_init, _params, state)
       when action not in [:spec, :log_metadata] do
    {{:error, :invalid_action}, state}
  end

  defp do_handle_action({:log_metadata, metadata}, _cb, _params, state) do
    Membrane.Logger.warn("""
    `log_metadata` action is deprecated.
    Use `log_metadata` field in `Membrane.ParentSpec` instead.
    """)

    Parent.LifecycleController.handle_log_metadata(metadata, state)
  end

  defp do_handle_action({:forward, children_messages}, _cb, _params, state) do
    Parent.ChildLifeController.handle_forward(Bunch.listify(children_messages), state)
  end

  defp do_handle_action({:spec, spec = %ParentSpec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- Parent.ChildLifeController.handle_spec(spec, state),
         do: {:ok, state}
  end

  defp do_handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_child(children, state)
  end

  defp do_handle_action({:remove_link, links}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_link(links, state)
  end

  defp do_handle_action({:start_timer, {id, interval, clock}}, _cb, _params, state) do
    TimerController.start_timer(id, interval, clock, state)
  end

  defp do_handle_action({:start_timer, {id, interval}}, cb, params, state) do
    clock = state.synchronization.clock_proxy
    do_handle_action({:start_timer, {id, interval, clock}}, cb, params, state)
  end

  defp do_handle_action({:timer_interval, {id, interval}}, cb, _params, state)
       when interval != :no_interval or cb == :handle_tick do
    TimerController.timer_interval(id, interval, state)
  end

  defp do_handle_action({:stop_timer, id}, _cb, _params, state) do
    TimerController.stop_timer(id, state)
  end

  defp do_handle_action(action, callback, _params, state) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {state.module, callback}
  end
end
