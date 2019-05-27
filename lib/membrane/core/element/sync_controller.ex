defmodule Membrane.Core.Element.SyncController do
  require Membrane.Element.CallbackContext.Other
  alias Membrane.Core.Element.ActionHandler
  alias Membrane.Core.CallbackHandler
  alias Membrane.Element.CallbackContext

  def handle_sync(sync, state) do
    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_sync,
             ActionHandler,
             %{sync: sync},
             [sync, CallbackContext.Other.from_state(state)],
             state
           ),
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_synced,
             ActionHandler,
             [sync, CallbackContext.Other.from_state(state)],
             state
           ) do
      {:ok, state}
    end
  end
end
