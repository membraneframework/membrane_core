defmodule Membrane.Element.Base.Mixin.CommonFuncs do
  @moduledoc """
  This module is a mixin with common functions.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Mixins.Log


      # Sends buffer to all linked destinations, final case when list is empty
      defp send_buffer_loop(_buffer, []) do
        :ok
      end


      # Sends buffer to all linked destinations, recurrent case when list is non-empty
      defp send_buffer_loop(buffer, [link_destinations_head|link_destinations_tail]) when is_tuple(buffer) do
        send(link_destinations_head, {:membrane_buffer, buffer})
        send_buffer_loop(buffer, link_destinations_tail)
      end


      # Sends buffer list to all linked destinations, final case when buffer list is empty
      defp send_buffer_list_loop([], _link_destinations) do
        :ok
      end


      # Sends buffer list to all linked destinations, recurrent case when buffer list is non-empty
      defp send_buffer_list_loop([buffer_head|buffer_tail], link_destinations) when is_tuple(buffer_head) do
        :ok = send_buffer_loop(buffer_head, link_destinations)
        send_buffer_list_loop(buffer_tail, link_destinations)
      end
    end
  end
end
