defmodule Membrane.Element.Base.Mixin.CommonCalls do
  @moduledoc false

  # This module is a mixin with common routines for all elements regarding
  # calls they may receive.


  defmacro __using__(_) do
    quote location: :keep do
      @doc false
      def handle_call(:membrane_prepare, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            case __MODULE__.handle_prepare(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Prepare: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :prepared, element_state: new_element_state}}

              {:error, reason} ->
                warn("Handle Prepare: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :prepared ->
            warn("Handle Prepare: Error, already prepared")
            # Do nothing if already prepared
            {:reply, :noop, state}

          :playing ->
            warn("Handle Prepare: Error, already playing")
            # Do nothing if already playing
            {:reply, :noop, state}
        end
      end


      @doc false
      def handle_call(:membrane_play, from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            case __MODULE__.handle_prepare(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Play: Prepared, new state = #{inspect(new_element_state)}")
                handle_call(:membrane_play, from, %{state | playback_state: :prepared, element_state: new_element_state})

              {:error, reason} ->
                warn("Handle Play: Error while preparing, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :prepared ->
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


      @doc false
      def handle_call(:membrane_stop, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            warn("Handle Stop: Error, already stopped")
            # Do nothing if already stopped
            {:reply, :noop, state}

          :prepared ->
            case __MODULE__.handle_stop(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Stop: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :stopped, element_state: new_element_state}}

              {:error, reason} ->
                warn("Handle Stop: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :playing ->
            case __MODULE__.handle_stop(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Stop: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :stopped, element_state: new_element_state}}

              {:error, reason} ->
                warn("Handle Stop: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end
        end
      end
    end
  end
end
