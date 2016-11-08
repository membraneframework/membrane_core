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
    quote do
      use GenServer


      def start_link(options) do
        GenServer.start_link(__MODULE__, options)
      end


      def play(server) do
        GenServer.call(server, :membrane_play)
      end


      def stop(server) do
        GenServer.call(server, :membrane_stop)
      end


      # Callbacks

      @doc false
      def init(options) do
        {:ok, element_state} = __MODULE__.handle_prepare(options)
        # TODO handle errors

        {:ok, %{
          playback_state: :stopped,
          element_state: element_state
        }}
      end


      def handle_call(:membrane_play, _from, %{playback_state: playback_state, element_state: element_state} = state) do
        case playback_state do
          :stopped ->
            case __MODULE__.handle_play(element_state) do
              {:ok, new_element_state} ->
                {:noreply, %{state | playback_state: :started, lement_state: new_element_state}}

              {:error, reason} ->
                {:noreply, state} # FIXME handle errors
            end

          :started ->
            # Do nothing if already started
            {:noreply, state}
        end
      end


      # Default implementations

      def handle_prepare(_options), do: %{}


      def handle_play(_options), do: %{}


      def handle_stop(_options), do: %{}


      defoverridable [
        handle_prepare: 1,
        handle_play: 1,
        handle_stop: 1,
      ]
    end
  end
end
