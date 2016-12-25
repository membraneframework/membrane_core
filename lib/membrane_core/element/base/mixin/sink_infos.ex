defmodule Membrane.Element.Base.Mixin.SinkInfos do
  @moduledoc false

  defmacro __using__(_) do
    quote location: :keep do
      @doc """
      Callback invoked on incoming buffer.

      If element is playing it will delegate actual processing to handle_buffer/3.

      Otherwise it will silently drop the buffer.
      """
      def handle_info({:membrane_buffer, buffer}, %{element_state: element_state, playback_state: playback_state} = state) do
        case playback_state do
          :stopped ->
            warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
            {:noreply, state}

          :prepared ->
            warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
            {:noreply, state}

          :playing ->
            handle_buffer(buffer, element_state) |> handle_callback(state)
        end
      end
    end
  end
end
