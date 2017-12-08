defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  alias Membrane.Mixins.Playback

  @callback is_membrane_element :: true

  @callback manager_module :: module

  @type callback_ret_t ::
    {:ok, any} |
    {:ok, list(), any} |
    {:error, any}

  @callback handle_init(Membrane.Element.element_options_t) ::
    {:ok, any} |
    {:error, any}

  @callback handle_prepare(Playback.state_t, Playback.state_t) :: callback_ret_t

  @callback handle_play(any) :: callback_ret_t

  @callback handle_stop(any) :: callback_ret_t

  @callback handle_other(Membrane.Message.type_t, any) :: callback_ret_t

  #TODO pad_t
  @callback handle_pad_added(any, :sink | :source, any) :: callback_ret_t

  @callback handle_pad_removed(any, any) :: callback_ret_t

  @callback handle_caps(any, Membrane.Caps.t, any, any) :: callback_ret_t

  @callback handle_event(any, Membrane.Event.type_t, any, any) :: callback_ret_t

  @callback handle_shutdown(any) :: :ok

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.CommonBehaviour

      use Membrane.Mixins.Log, tags: :element, import: false

      # Default implementations

      @doc """
      Enables to check whether module is membrane element
      """
      def is_membrane_element, do: true

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
      def handle_pad_added(_pad, _direction, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_caps(_pad, _caps, _params, state), do: {:ok, state}

      @doc false
      def handle_event(_pad, _event, _params, state), do: {:ok, state}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_init: 1,
        handle_prepare: 2,
        handle_play: 1,
        handle_stop: 1,
        handle_other: 2,
        handle_pad_added: 3,
        handle_pad_removed: 2,
        handle_caps: 4,
        handle_event: 4,
        handle_shutdown: 1,
      ]
    end
  end
end
