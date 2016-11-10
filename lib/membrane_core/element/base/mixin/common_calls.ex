defmodule Membrane.Element.Base.Mixin.CommonCalls do
  @moduledoc """
  This module is a mixin with common routines for all elements regarding
  calls they may receive.
  """


  defmacro __using__(_) do
    quote location: :keep do
      def handle_call(:membrane_play, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            case __MODULE__.handle_play(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Play: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :playing, element_state: new_element_state}}

              {:error, reason} ->
                warn("Handle Play: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :playing ->
            warn("Handle Play: Error, already playing")
            # Do nothing if already playing
            {:reply, :noop, state}
        end
      end


      def handle_call(:membrane_stop, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :playing ->
            case __MODULE__.handle_stop(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Stop: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :stopped, element_state: new_element_state}}

              {:error, reason} ->
                warn("Handle Stop: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :stopped ->
            warn("Handle Stop: Error, already stopped")
            # Do nothing if already stopped
            {:reply, :noop, state}
        end
      end
    end
  end
end
