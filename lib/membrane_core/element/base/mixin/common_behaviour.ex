defmodule Membrane.Element.Base.Mixin.CommonBehaviour do

  @callback manager_module :: module

  @callback handle_init(Membrane.Element.element_options_t) ::
    {:ok, any} |
    {:error, any}

  @callback handle_shutdown(any) :: any

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.CommonBehaviour

      # Default implementations

      @doc false
      def handle_init(_options), do: {:ok, %{}}

      @doc false
      def handle_prepare(_previous_playback_state, state), do: {:ok, state}

      @doc false
      def handle_play(state), do: {:ok, state}

      @doc false
      def handle_stop(state), do: {:ok, state}

      @doc false
      def handle_other(_message, state), do: {:ok, state}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_init: 1,
        handle_prepare: 2,
        handle_play: 1,
        handle_stop: 1,
        handle_other: 2,
        handle_shutdown: 1,
      ]
    end
  end
end
