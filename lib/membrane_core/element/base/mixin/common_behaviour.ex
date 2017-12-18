defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  alias Membrane.Mixins.Playback
  alias Membrane.Element.Manager.State
  alias Membrane.Element.Context

  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:buffer, {Membrane.Pad.name_t, Membrane.Buffer.t}} |
    {:caps, {Membrane.Pad.name_t, Membrane.Caps.t}} |
    {:event, {Membrane.Pad.name_t, Membrane.Event.t}} |
    {:message, Membrane.Message.t}

  # Type that defines list of actions that may be returned from handle_*
  # callbacks.
  @type callback_actions_t :: list(callback_action_t)

  # Type that defines all valid return values from callbacks.
  @type callback_return_t ::
    {{:ok, callback_actions_t}, State.internal_state_t} |
    {{:error, any}, State.internal_state_t}


  @callback is_membrane_element :: true

  @callback manager_module :: module

  @callback handle_init(Membrane.Element.element_options_t) ::
    {:ok, State.internal_state_t} |
    {:error, State.internal_state_t}


  @doc """
  Callback invoked when Element is prepared. It will receive the previous
  internal state.

  Normally this is the place where you will allocate most of the resources
  used by the Element. For example, if your Element opens a file, this is
  the place to try to actually open it and return error if that has failed.

  Such resources should be released in `handle_stop/1`.
  """
  @callback handle_prepare(Playback.state_t, Playback.state_t) :: callback_return_t


  @doc """
  Callback invoked when Element is supposed to start playing. It will receive
  previous internal state.

  This is moment when you should start generating buffers if there're any
  pads in the push mode.
  """
  @callback handle_play(State.internal_state_t) :: callback_return_t


  @doc """
  Callback invoked when Element is supposed to stop playing. It will receive
  previous internal state.

  Normally this is the place where you will release most of the resources
  used by the Element. For example, if your Element opens a file, this is
  the place to close it.
  """
  @callback handle_stop(State.internal_state_t) :: callback_return_t


  @doc """
  Callback invoked when Element is receiving message of other kind.

  The arguments are:

  * message,
  * current element's sate.
  """
  @callback handle_other(Membrane.Message.type_t, State.internal_state_t) :: callback_return_t

  @doc """
  Callback that is called when new pad has beed added to element.

  The arguments are:

  * name of the pad,
  * context (`Membane.Element.Context.PadAdded`),
  * current internal state.
  """
  @callback handle_pad_added(Membrane.Element.Pad.name_t, Context.PadAdded.t, State.internal_state_t) :: callback_return_t


  @doc """
  Callback that is called when some pad of the element has beed removed.

  The arguments are:

  * name of the pad,
  * context (`Membrane.Element.Context.PadRemoved`)
  * current internal state.
  """
  @callback handle_pad_removed(Membrane.Element.Pad.name_t, Context.PadRemoved.t, State.internal_state_t) :: callback_return_t


  @doc """
  Callback invoked when Element.Manager is receiving information about new caps for
  given pad.

  The arguments are:

  * name of the pad receiving caps,
  * new caps of this pad,
  * context (`Membrane.Element.Context.Caps`)
  * current internal state
  """
  @callback handle_caps(Membrane.Element.Pad.name_t, Membrane.Caps.t, Context.Caps.t, State.internal_state_t) :: callback_return_t


  @doc """
  Callback that is called when event arrives.

  The arguments are:

  * name of the pad receiving an event,
  * event,
  * context (`Membrane.Element.Context.Event`)
  * current Element.Manager state.
  """
  @callback handle_event(Membrane.Element.Pad.name_t, Membrane.Event.type_t, Context.Event.t, State.internal_state_t) :: callback_return_t


  @doc """
  Callback invoked when element is shutting down just before process is exiting.
  It will receive the element state.
  """
  @callback handle_shutdown(State.internal_state_t) :: :ok


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
      def handle_pad_added(_pad, _context, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, _context, state), do: {:ok, state}

      @doc false
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      @doc false
      def handle_event(_pad, _event, _context, state), do: {:ok, state}

      @doc false
      def handle_shutdown(_state), do: :ok


      defoverridable [
        handle_init: 1,
        handle_prepare: 2,
        handle_play: 1,
        handle_stop: 1,
        handle_other: 2,
        handle_pad_added: 3,
        handle_pad_removed: 3,
        handle_caps: 4,
        handle_event: 4,
        handle_shutdown: 1,
      ]
    end
  end
end
