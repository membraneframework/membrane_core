defmodule Membrane.Element.Base.Mixin.Process do
  @moduledoc """
  This module is a mixin with common routines regarding spawning element
  as a process.

  You should not use this directly unless you know what are you doing
  """


  @doc """
  Callback invoked when element is initialized. It will receive options
  passed to start_link.
  """
  @callback handle_prepare(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is supposed to start playing. It will receive
  element state.
  """
  @callback handle_play(any) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when element is supposed to stop playing. It will receive
  element state.
  """
  @callback handle_stop(any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote location: :keep do
      use GenServer
      use Membrane.Mixins.Log


      def start_link(options) do
        debug("Start Link: options = #{inspect(options)}")
        GenServer.start_link(__MODULE__, options)
      end


      def play(server) do
        debug("Play -> #{inspect(server)}")
        GenServer.call(server, :membrane_play)
      end


      def stop(server) do
        debug("Stop -> #{inspect(server)}")
        GenServer.call(server, :membrane_stop)
      end


      # Callbacks

      @doc false
      def init(options) do
        {:ok, element_state} = __MODULE__.handle_prepare(options)
        # TODO handle errors

        debug("Initial state: #{inspect(element_state)}")

        {:ok, %{
          playback_state: :stopped,
          link_destinations: [],
          element_state: element_state
        }}
      end


      def handle_call(:membrane_play, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            case __MODULE__.handle_play(element_state) do
              {:ok, new_element_state} ->
                debug("Handle Play: OK, new state = #{inspect(new_element_state)}")
                {:reply, :ok, %{state | playback_state: :playing, element_state: new_element_state}}

              {:error, reason} ->
                debug("Handle Play: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :playing ->
            debug("Handle Play: Already playing")
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
                debug("Handle Stop: Error, reason = #{inspect(reason)}")
                {:reply, {:error, reason}, state} # FIXME handle errors
            end

          :stopped ->
            debug("Handle Stop: Already stopped")
            # Do nothing if already stopped
            {:reply, :noop, state}
        end
      end


      # Sends buffer to all linked destinations, final case when list is empty
      defp send_buffer_loop(_caps, _data, []) do
        :ok
      end


      # Sends buffer to all linked destinations, recurrent case when list is non-empty
      defp send_buffer_loop(caps, data, [head|tail]) do
        send(head, {:membrane_buffer, {caps, data}})
        send_buffer_loop(caps, data, tail)
      end


      defp send_buffer_list_loop([], _link_destinations) do
        :ok
      end


      defp send_buffer_list_loop([{caps, data}|buffer_tail], link_destinations) do
        :ok = send_buffer_loop(caps, data, link_destinations)
        send_buffer_list_loop(buffer_tail, link_destinations)
      end


      # Default implementations

      def handle_prepare(_options), do: {:ok, %{}}


      def handle_play(state), do: {:ok, state}


      def handle_stop(state), do: {:ok, state}


      defoverridable [
        handle_prepare: 1,
        handle_play: 1,
        handle_stop: 1,
      ]
    end
  end
end
