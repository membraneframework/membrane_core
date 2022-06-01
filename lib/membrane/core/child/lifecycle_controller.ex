defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  alias Membrane.Core.{CallbackHandler, Component}

  require Membrane.Core.Component

  @type state_t ::
          Membrane.Core.Bin.State.t()
          | Membrane.Core.Element.State.t()

  @spec handle_parent_notification(Membrane.ParentNotification.t(), state_t) ::
          state_t
  def handle_parent_notification(notification, state) do
    context = Component.callback_context_generator(:child, ParentNotification, state)

    action_handler =
      if Component.is_bin?(state),
        do: Membrane.Core.Bin.ActionHandler,
        else: Membrane.Core.Element.ActionHandler

    CallbackHandler.exec_and_handle_callback(
      :handle_parent_notification,
      action_handler,
      %{context: context},
      notification,
      state
    )
  end
end
