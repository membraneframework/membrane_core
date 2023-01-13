defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  alias Membrane.Core.{CallbackHandler, Component}

  require Membrane.Core.Component

  @spec handle_parent_notification(Membrane.ParentNotification.t(), Membrane.Core.Child.state()) ::
          Membrane.Core.Child.state()
  def handle_parent_notification(notification, state) do
    action_handler = Component.action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_parent_notification,
      action_handler,
      %{context: &Component.context_from_state/1},
      notification,
      state
    )
  end
end
