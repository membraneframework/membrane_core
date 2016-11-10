defmodule Membrane.Element.Base.Mixin.CommonProcess do
  @moduledoc """
  This module is a mixin with common routines for all elements regarding
  their process lifecycle.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use GenServer


      def start_link(options) do
        debug("Start Link: options = #{inspect(options)}")
        GenServer.start_link(__MODULE__, options)
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
    end
  end
end
