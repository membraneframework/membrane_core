defmodule Membrane.Element.Base.Mixin.CommonFuncs do
  @moduledoc false

  # This module is a mixin with functions common to all elements.


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Mixins.Log


      # Generic handler that can be used to convert return value from
      # element callback to reply that is accepted by GenServer.handle_info.
      #
      # Case when callback returned success and requests no further action.
      defp handle_callback({:ok, new_element_state}, state) do
        debug("Handle callback: OK")
        {:noreply, %{state | element_state: new_element_state}}
      end


      # Generic handler that can be used to convert return value from
      # element callback to reply that is accepted by GenServer.handle_info.
      #
      # Case when callback returned success and wants to send some messages
      # (such as buffers) in response.
      defp handle_callback({:ok, commands, new_element_state}, state) do
        debug("Handle callback: OK + commands #{inspect(commands)}")
        :ok = handle_commands(commands, state)
        {:noreply, %{state | element_state: new_element_state}}
      end


      # Generic handler that can be used to convert return value from
      # element callback to reply that is accepted by GenServer.handle_info.
      #
      # Case when callback returned failure.
      defp handle_callback({:error, reason, new_element_state}, state) do
        warn("Handle callback: Error (reason = #{inspect(reason)}")
        {:noreply, %{state | element_state: new_element_state}}
        # TODO handle errors
      end


      defp handle_commands([], state) do
        {:ok, state}
      end


      # Handles command that is supposed to send buffer of event from the
      # given pad to its linked peer.
      defp handle_commands([{:send, {pad, buffer_or_event}}|tail], state) do
        # :ok = send_message(head, link_destinations)

        handle_commands(tail, state)
      end


      # Handles command that is informs that caps on given pad were set.
      #
      # If this pad has a peer it will additionally send Membrane.Event.caps
      # to it.
      defp handle_commands([{:caps, {pad, caps}}|tail], state) do
        # :ok = send_message(head, link_destinations)

        handle_commands(tail, state)
      end
    end
  end
end
