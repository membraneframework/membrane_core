defmodule Membrane.Element.Base.Mixin.CommonFuncs do
  @moduledoc """
  This module is a mixin with functions common to all elements.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Mixins.Log


      defp handle_callback({:ok, new_element_state}, state) do
        debug("Handle callback: OK")
        {:noreply, %{state | element_state: new_element_state}}
      end


      defp handle_callback({:send, message_list, new_element_state}, %{link_destinations: link_destinations} = state) do
        debug("Handle callback: OK + send #{inspect(message_list)}")
        :ok = send_message_list_loop(message_list, link_destinations)
        {:noreply, %{state | element_state: new_element_state}}
      end


      defp handle_callback({:error, reason, new_element_state}, state) do
        warn("Handle callback: Error (reason = #{inspect(reason)}")
        {:noreply, %{state | element_state: new_element_state}}
        # TODO handle errors
      end


      # Sends buffer to all linked destinations, final case when list is empty
      defp send_message_loop(_buffer, []) do
        :ok
      end


      # Sends buffer to all linked destinations, recurrent case when list is non-empty
      defp send_message_loop(buffer, [link_destinations_head|link_destinations_tail]) when is_tuple(buffer) do
        send(link_destinations_head, {:membrane_buffer, buffer})
        send_message_loop(buffer, link_destinations_tail)
      end


      # Sends buffer list to all linked destinations, final case when buffer list is empty
      defp send_message_list_loop([], _link_destinations) do
        :ok
      end


      # Sends buffer list to all linked destinations, recurrent case when buffer list is non-empty
      defp send_message_list_loop([buffer_head|buffer_tail], link_destinations) when is_tuple(buffer_head) do
        :ok = send_message_loop(buffer_head, link_destinations)
        send_message_list_loop(buffer_tail, link_destinations)
      end
    end
  end
end
