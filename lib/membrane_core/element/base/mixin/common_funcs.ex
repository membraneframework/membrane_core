defmodule Membrane.Element.Base.Mixin.CommonFuncs do
  @moduledoc """
  This module is a mixin with functions common to all elements.
  """


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
      defp handle_callback({:ok, commands, new_element_state}, %{link_destinations: link_destinations} = state) do
        debug("Handle callback: OK + commands #{inspect(commands)}")
        :ok = send_commands(commands, link_destinations)
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


      # Sends message to all linked destinations, final case when list is empty
      defp send_message(_message, []) do
        :ok
      end


      # Sends message to all linked destinations, recurrent case when list
      # is non-empty and message is a buffer
      defp send_message(%Membrane.Buffer{} = buffer, [link_destinations_head|link_destinations_tail])  do
        send(link_destinations_head, {:membrane_buffer, buffer})
        send_message(buffer, link_destinations_tail)
      end


      # Sends message list to all linked destinations, final case when message
      # list is empty
      defp send_commands([], _link_destinations) do
        :ok
      end


      # Sends message list to all linked destinations, recurrent case when
      # message list is non-empty
      defp send_commands([message_head|message_tail], link_destinations) do
        :ok = send_message(message_head, link_destinations)
        send_commands(message_tail, link_destinations)
      end
    end
  end
end
