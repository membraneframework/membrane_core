defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  alias Membrane.Core.{CallbackHandler, Component}

  require Membrane.Core.Component

  @spec handle_parent_notification(Membrane.ParentNotification.t(), Membrane.Core.Child.state_t()) ::
          Membrane.Core.Child.state_t()
  def handle_parent_notification(notification, state) do
    context = Component.callback_context_generator(:child, ParentNotification, state)
    action_handler = Component.action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_parent_notification,
      action_handler,
      %{context: context},
      notification,
      state
    )
  end
end
