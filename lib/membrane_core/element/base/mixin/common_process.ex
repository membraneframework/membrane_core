defmodule Membrane.Element.Base.Mixin.CommonProcess do
  @moduledoc false

  # This module is a mixin with common routines for all elements regarding
  # their process lifecycle.


  defmacro __using__(_) do
    quote location: :keep do
      use GenServer


      # Callbacks

      @doc false
      @spec init(struct) :: {:ok, map} | {:error, any}
      def init(options) do
        # Call element initialization callback
        case __MODULE__.handle_init(options) do
          {:ok, element_state} ->
            debug("Initialized: element_state = #{inspect(element_state)}")

            # Store module name in the process dictionary so it can be used
            # to retreive module from PID in `Membrane.Element.get_module/1`.
            Process.put(:membrane_element_module, __MODULE__)

            # Return initial state of the server, including element state.
            {:ok, %{
              playback_state: :stopped,
              source_pads: known_source_pads() |> known_pads_to_pads_state,
              sink_pads: known_sink_pads() |> known_pads_to_pads_state,
              element_state: element_state
            }}

          {:error, reason} ->
            warn("Failed to initialize: reason = #{inspect(reason)}")
            {:stop, reason}
        end
      end


      @doc false
      def terminate(reason, %{playback_state: playback_state, element_state: element_state} = state) do
        if playback_state != :stopped do
          warn("Terminating: Attempt to terminate element when it is not stopped, state = #{inspect(state)}")
        end

        debug("Terminating: reason = #{inspect(reason)}, state = #{inspect(state)}")
        __MODULE__.handle_shutdown(element_state)
      end


      defp known_pads_to_pads_state(known_pads) do
        known_pads
        |> Map.to_list
        |> Enum.filter(fn({_name, {availability, _caps}}) ->
          availability == :always
        end)
        |> Enum.reduce(%{}, fn({name, {_availability, _caps}}, acc) ->
          acc |> Map.put(name, %{peer: nil, caps: nil})
        end)
      end
    end
  end
end
