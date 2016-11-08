defmodule Membrane.Element.Base.Mixin.Sink do
  @doc """
  Callback that is called when buffer arrives.

  The arguments are:

  - caps
  - data
  - current element state

  While implementing these callbacks, please use pattern matching to define
  what caps are supported. In other words, define one function matching this
  signature per each caps supported.
  """
  @callback handle_buffer(%Membrane.Caps{}, bitstring, any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.Sink


      @doc """
      Callback invoked on incoming buffer.

      If element is playing it will delegate actual processing to handle_buffer/3.

      Otherwise it will silently drop the buffer.
      """
      def handle_info({:membrane_buffer, {caps, data}}, %{link_destinations: link_destinations, playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :playing ->
            case handle_buffer(caps, data, element_state) do
              {:ok, new_element_state} ->
                debug("Incoming buffer: OK (caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)})")
                {:noreply, %{state | element_state: new_element_state}}

              {:send_buffer, {caps_to_send, data_to_send}, new_element_state} ->
                debug("Incoming buffer: OK + send buffer #{inspect(caps_to_send)}, #{inspect(data_to_send)} (caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)})")
                :ok = send_buffer_loop(caps_to_send, data_to_send, link_destinations)
                {:noreply, %{state | element_state: new_element_state}}

              {:send_buffer, buffer_list, new_element_state} ->
                debug("Incoming buffer: OK + send buffer_list #{inspect(buffer_list)} (caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)})")
                :ok = send_buffer_list_loop(buffer_list, link_destinations)
                {:noreply, %{state | element_state: new_element_state}}

              {:error, reason} ->
                debug("Incoming buffer: Error (reason = #{inspect(reason)}, caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)})")
                {:noreply, state}
                # TODO handle errors
            end

          :stopped ->
            debug("Incoming buffer: Error, not started (caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)})")
            {:noreply, state}
        end
      end
    end
  end
end
