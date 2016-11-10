defmodule Membrane.Element.Base.Mixin.CommonInfos do
  @moduledoc """
  This module is a mixin with common routines for all elements regarding
  infos they may receive.
  """


  defmacro __using__(_) do
    quote location: :keep do
      def handle_info(message, %{link_destinations: link_destinations, element_state: element_state} = state) do
        case __MODULE__.handle_other(message, element_state) do
          {:ok, new_element_state} ->
            debug("Handle other: OK (message = #{inspect(message)})")
            {:noreply, %{state | element_state: new_element_state}}

          {:send_buffer, %Membrane.Buffer{} = buffer, new_element_state} ->
            debug("Handle other: OK + send buffer #{inspect(buffer)} (message = #{inspect(message)})")
            :ok = send_buffer_loop(buffer, link_destinations)
            {:noreply, %{state | element_state: new_element_state}}

          {:send_buffer, buffer_list, new_element_state} ->
            debug("Handle other: OK + send buffer_list #{inspect(buffer_list)} (message = #{inspect(message)})")
            :ok = send_buffer_list_loop(buffer_list, link_destinations)
            {:noreply, %{state | element_state: new_element_state}}

          {:error, reason} ->
            warn("Handle other: Error (reason = #{inspect(reason)}, (message = #{inspect(message)})")
            {:noreply, state}
            # TODO handle errors
        end
      end
    end
  end
end
