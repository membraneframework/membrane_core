defmodule Membrane.Core.Bin.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler
  require Membrane.Logger
  alias Membrane.{CallbackError, Core, Notification, ParentSpec}
  alias Core.{Parent, Message}
  alias Core.Bin.State

  require Message

  @impl CallbackHandler
  def handle_action({:forward, {child_name, message}}, _cb, _params, state) do
    Parent.ChildLifeController.handle_forward(child_name, message, state)
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
  def handle_action({:notify, notification}, _cb, _params, state) do
    send_notification(notification, state)
  end

  @impl CallbackHandler
  def handle_action({:log_metadata, metadata}, _cb, _params, state) do
    Parent.LifecycleController.handle_log_metadata(metadata, state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, _params, state) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {state.module, callback}
  end

  @spec send_notification(Notification.t(), State.t()) :: {:ok, State.t()}
  defp send_notification(notification, %State{watcher: nil} = state) do
    Membrane.Logger.debug(
      "Dropping notification #{inspect(notification)} as watcher is undefined"
    )

    {:ok, state}
  end

  defp send_notification(notification, %State{watcher: watcher, name: name} = state) do
    Membrane.Logger.debug(
      "Sending notification #{inspect(notification)} (watcher: #{inspect(watcher)})"
    )

    Message.send(watcher, :notification, [name, notification])
    {:ok, state}
  end
end
