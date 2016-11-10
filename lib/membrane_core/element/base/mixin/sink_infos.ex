defmodule Membrane.Element.Base.Mixin.SinkInfos do
  defmacro __using__(_) do
    quote location: :keep do
      @doc """
      Callback invoked on incoming buffer.

      If element is playing it will delegate actual processing to handle_buffer/3.

      Otherwise it will silently drop the buffer.
      """
      def handle_info({:membrane_buffer, buffer}, %{link_destinations: link_destinations, playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :playing ->
            case handle_buffer(buffer, element_state) do
              {:ok, new_element_state} ->
                debug("Incoming buffer: OK (buffer = #{inspect(buffer)})")
                {:noreply, %{state | element_state: new_element_state}}

              {:send_buffer, %Membrane.Buffer{} = buffer, new_element_state} ->
                debug("Incoming buffer: OK + send buffer #{inspect(buffer)} (buffer = #{inspect(buffer)})")
                :ok = send_buffer_loop(buffer, link_destinations)
                {:noreply, %{state | element_state: new_element_state}}

              {:send_buffer, buffer_list, new_element_state} ->
                debug("Incoming buffer: OK + send buffer_list #{inspect(buffer_list)} (buffer = #{inspect(buffer)})")
                :ok = send_buffer_list_loop(buffer_list, link_destinations)
                {:noreply, %{state | element_state: new_element_state}}

              {:error, reason} ->
                warn("Incoming buffer: Error #{inspect(reason)} (buffer = #{inspect(buffer)})")
                {:noreply, state}
                # TODO handle errors
            end

          :stopped ->
            warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
            {:noreply, state}
        end
      end
    end
  end
end
