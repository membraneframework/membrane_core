defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  alias Membrane.{Element, Message}
  alias Element.{Action, Context, Pad}
  alias Element.Manager.State
  alias Element.Base.Mixin
  alias Membrane.Mixins.{Playback, CallbackHandler}

  @typedoc """
  Type that defines all valid return values from callbacks.
  """
  @type callback_return_t ::
          CallbackHandler.callback_return_t(Action.t(), State.internal_state_t())

  @type known_pads_t ::
          Mixin.SinkBehaviour.known_sink_pads_t() | Mixin.SourceBehaviour.known_source_pads_t()

  @callback is_membrane_element :: true

  @doc """
  Returns module that manages this element.
  """
  @callback manager_module :: module

  @callback handle_init(Element.element_options_t()) ::
              {:ok, State.internal_state_t()}
              | {:error, any}

  @doc """
  Callback invoked when Element is prepared. It will receive the previous
  internal state.

  Normally this is the place where you will allocate most of the resources
  used by the Element. For example, if your Element opens a file, this is
  the place to try to actually open it and return error if that has failed.

  Such resources should be released in `handle_stop/1`.
  """
  @callback handle_prepare(Playback.state_t(), State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when Element is supposed to start playing. It will receive
  previous internal state.

  This is moment when you should start generating buffers if there're any
  pads in the push mode.
  """
  @callback handle_play(State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when Element is supposed to stop playing. It will receive
  previous internal state.

  Normally this is the place where you will release most of the resources
  used by the Element. For example, if your Element opens a file, this is
  the place to close it.
  """
  @callback handle_stop(State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when Element is receiving message of other kind.

  The arguments are:

  * message,
  * current element's sate.
  """
  @callback handle_other(Message.type_t(), State.internal_state_t()) :: callback_return_t

  @doc """
  Callback that is called when new pad has beed added to element.

  The arguments are:

  * name of the pad,
  * context (`Membane.Element.Context.PadAdded`),
  * current internal state.
  """
  @callback handle_pad_added(Pad.name_t(), Context.PadAdded.t(), State.internal_state_t()) ::
              callback_return_t

  @doc """
  Callback that is called when some pad of the element has beed removed.

  The arguments are:

  * name of the pad,
  * context (`Membrane.Element.Context.PadRemoved`)
  * current internal state.
  """
  @callback handle_pad_removed(Pad.name_t(), Context.PadRemoved.t(), State.internal_state_t()) ::
              callback_return_t

  @doc """
  Callback invoked when Element.Manager is receiving information about new caps for
  given pad.

  The arguments are:

  * name of the pad receiving caps,
  * new caps of this pad,
  * context (`Membrane.Element.Context.Caps`)
  * current internal state
  """
  @callback handle_caps(
              Pad.name_t(),
              Membrane.Caps.t(),
              Context.Caps.t(),
              State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when event arrives.

  The arguments are:

  * name of the pad receiving an event,
  * event,
  * context (`Membrane.Element.Context.Event`)
  * current Element.Manager state.
  """
  @callback handle_event(
              Pad.name_t(),
              Event.type_t(),
              Context.Event.t(),
              State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element is shutting down just before process is exiting.
  It will receive the element state.
  """
  @callback handle_shutdown(State.internal_state_t()) :: :ok

  @doc """
  Macro that defines known options for the element type.

  It automatically generates appropriate struct.
  """
  defmacro def_options(options) do
    quote do
      @spec options() :: keyword
      def options(), do: unquote(options)

      @enforce_keys unquote(options)
                    |> Enum.flat_map(fn {k, v} ->
                      if v |> Map.new() |> Map.has_key?(:default) |> Kernel.not(),
                        do: [k],
                        else: []
                    end)

      defstruct unquote(options)
                |> Enum.map(fn {k, v} -> {k, v[:default]} end)
    end
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      use Membrane.Mixins.Log, tags: :element, import: false

      alias Membrane.Element.Context, as: Ctx

      import unquote(__MODULE__), only: [def_options: 1]

      @impl true
      def is_membrane_element, do: true

      @impl true
      def handle_init(_options), do: {:ok, %{}}

      @impl true
      def handle_prepare(_previous_playback_state, state), do: {:ok, state}

      @impl true
      def handle_play(state), do: {:ok, state}

      @impl true
      def handle_stop(state), do: {:ok, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_pad_added(_pad, _context, state), do: {:ok, state}

      @impl true
      def handle_pad_removed(_pad, _context, state), do: {:ok, state}

      @impl true
      def handle_caps(_pad, _caps, _context, state), do: {:ok, state}

      @impl true
      def handle_event(_pad, _event, _context, state), do: {:ok, state}

      @impl true
      def handle_shutdown(_state), do: :ok

      defoverridable handle_init: 1,
                     handle_prepare: 2,
                     handle_play: 1,
                     handle_stop: 1,
                     handle_other: 2,
                     handle_pad_added: 3,
                     handle_pad_removed: 3,
                     handle_caps: 4,
                     handle_event: 4,
                     handle_shutdown: 1
    end
  end
end
