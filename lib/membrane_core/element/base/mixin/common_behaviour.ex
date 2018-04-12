defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc """
  Module defining behaviour common to all elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.
  """
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

  @callback membrane_element? :: true

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

  @default_quoted_specs %{
    atom:
      quote do
        atom()
      end,
    boolean:
      quote do
        boolean()
      end,
    string:
      quote do
        String.t()
      end,
    keyword:
      quote do
        keyword()
      end
  }

  @doc """
  Macro that defines known options for the element type.

  It automatically generates appropriate struct.

  `def_options/1` should receive keyword list, where each key is option name and
  is described by another keyword list with following fields:

    * `type:` atom, used for parsing
    * `spec:` typespec for value in struct. If ommitted, for types:
      `#{inspect(Map.keys(@default_quoted_specs))}` the default typespec is provided.
      For others typespec is set to `t:any/0`
    * `default:` default value for option. If not present, value for this option
      will have to be provided each time options struct is created
    * `description:` string describing an option. It will be present in value returned by `options/0`
      and in typedoc for the struct.
  """
  defmacro def_options(options) do
    {opt_specs, escaped_opts} = extract_specs(options)
    opt_typespec_ast = {:%{}, [], Keyword.put(opt_specs, :__struct__, __CALLER__.module)}
    # opt_typespec_ast is equivalent of typespec %__CALLER__.module{key: value, ...}
    typedoc =
      options
      |> Enum.map_join("\n", fn {k, v} ->
        "* `#{Atom.to_string(k)}`: #{Keyword.get(v, :description, "\n")}"
        |> String.trim()
      end)

    quote do
      @typedoc """
      Struct containing options for `#{inspect(__MODULE__)}`
      #{unquote(typedoc)}
      """
      @type t :: unquote(opt_typespec_ast)

      @doc """
      Returns description of options available for this module
      """
      @spec options() :: keyword
      def options(), do: unquote(escaped_opts)

      @enforce_keys unquote(escaped_opts)
                    |> Enum.reject(fn {k, v} -> v |> Keyword.has_key?(:default) end)
                    |> Keyword.keys()

      defstruct unquote(escaped_opts)
                |> Enum.map(fn {k, v} -> {k, v[:default]} end)
    end
  end

  defp extract_specs({:%{}, _, kw}), do: extract_specs(kw)

  defp extract_specs(kw) when is_list(kw) do
    with_default_specs =
      kw
      |> Enum.map(fn {k, v} ->
        quoted_any =
          quote do
            any()
          end

        default_val =
          @default_quoted_specs
          |> Map.get(v[:type], quoted_any)

        {k, v |> Keyword.put_new(:spec, default_val)}
      end)

    opt_typespecs =
      with_default_specs
      |> Enum.map(fn {k, v} -> {k, v[:spec]} end)

    escaped_opts =
      with_default_specs
      |> Enum.map(fn {k, v} ->
        {k, v |> Keyword.update!(:spec, &Macro.to_string/1)}
      end)

    {opt_typespecs, escaped_opts}
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      use Membrane.Mixins.Log, tags: :element, import: false

      import unquote(__MODULE__), only: [def_options: 1]

      @impl true
      def membrane_element?, do: true

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
