defmodule Membrane.Element.Base do
  @moduledoc """
  Module defining behaviour common to all elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  # Elements

  Elements are units that produce, process or consume data. They can be linked
  with `Membrane.Pipeline`, and thus form a pipeline able to perform complex data
  processing. Each element defines a set of pads, through which it can be linked
  with other elements. During playback, pads can either send (output pads) or
  receive (input pads) data. For more information on pads, see
  `Membrane.Pad`.

  To implement an element, one of base modules (`Membrane.Source`,
  `Membrane.Filter`, `Membrane.Endpoint` or `Membrane.Sink`)
  has to be `use`d, depending on the element type:
  - source, producing buffers (contain only output pads),
  - filter, processing buffers (contain both input and output pads),
  - endpoint, producing and consuming buffers (contain both input and output pads),
  - sink, consuming buffers (contain only input pads).
  For more information on each element type, check documentation for appropriate
  base module.

  ## Behaviours
  Element-specific behaviours are specified in modules:
  - `Membrane.Element.Base` - this module, behaviour common to all
  elements,
  - `Membrane.Element.WithOutputPads` - behaviour common to sources,
  filters and endpoints
  - `Membrane.Element.WithInputPads` - behaviour common to sinks,
  filters and endpoints
  - Base modules (`Membrane.Source`, `Membrane.Filter`, `Membrane.Endpoint`,
  `Membrane.Sink`) - behaviours specific to each element type.

  ## Callbacks
  Modules listed above provide specifications of callbacks that define elements
  lifecycle. All of these callbacks have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions framework should undertake as a result, besides
  executing element-specific code.

  For actions that can be returned by each callback, see `Membrane.Element.Action`
  module.
  """

  use Bunch

  alias Membrane.Core.OptionsSpecs
  alias Membrane.{Element, Event, Pad}
  alias Membrane.Element.{Action, CallbackContext}

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t :: {[Action.t()], Element.state_t()}

  @doc """
  Callback invoked on initialization of element.

  This callback is synchronous: the parent waits until it finishes. Also, any failures
  that happen in this callback crash the parent as well, regardless of crash groups.
  For these reasons, it's important to do any long-lasting or complex work in `c:handle_setup/2`,
  while `handle_init` should be used for things like parsing options or initializing state.
  """
  @callback handle_init(context :: CallbackContext.Init.t(), options :: Element.options_t()) ::
              callback_return_t

  @doc """
  Callback invoked on element startup, right after `c:handle_init/2`.

  Any long-lasting or complex initialization should happen here.
  """
  @callback handle_setup(
              context :: CallbackContext.Setup.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when bin switches the playback to `:playing`.

  From this point, element can send and receive buffers, events, stream formats and demands
  through its pads.
  """
  @callback handle_playing(
              context :: CallbackContext.Playing.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_info(
              message :: any(),
              context :: CallbackContext.Info.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when new pad has beed added to element. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_added(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadAdded.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when some pad of the element has beed removed. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_removed(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadRemoved.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when event arrives.

  Events may arrive from both input and output pads. In filters by default event is
  forwarded to all output and input pads, respectively.
  """
  @callback handle_event(
              pad :: Pad.ref_t(),
              event :: Event.t(),
              context :: CallbackContext.Event.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked upon each timer tick. A timer can be started with `Membrane.Element.Action.start_timer_t`
  action.
  """
  @callback handle_tick(
              timer_id :: any,
              context :: CallbackContext.Tick.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when a message from the parent is received.
  """
  @callback handle_parent_notification(
              notification :: Membrane.ParentNotification.t(),
              context :: Membrane.Element.CallbackContext.ParentNotification.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element is removed by its parent.

  By default it returns `t:Membrane.Element.Action.terminate_t/0` with reason `:normal`.
  """
  @callback handle_terminate_request(
              context :: CallbackContext.TerminateRequest.t(),
              state :: Element.state_t()
            ) ::
              callback_return_t()

  @doc """
  A callback for constructing struct. Will be defined by `def_options/1` if used.

  See `defstruct/1` for a more in-depth description.
  """
  @callback __struct__() :: struct()

  @doc """
  A callback for constructing struct with values. Will be defined by `def_options/1` if used.

  See `defstruct/1` for a more in-depth description.
  """
  @callback __struct__(kv :: [atom | {atom, any()}]) :: struct()

  @optional_callbacks handle_init: 2,
                      handle_setup: 2,
                      handle_playing: 2,
                      handle_info: 3,
                      handle_pad_added: 3,
                      handle_pad_removed: 3,
                      handle_event: 4,
                      handle_tick: 3,
                      handle_parent_notification: 3,
                      __struct__: 0,
                      __struct__: 1

  @doc """
  Macro defining options that parametrize element.

  It automatically generates appropriate struct and documentation.

  #{OptionsSpecs.options_doc()}
  """
  defmacro def_options(options) do
    OptionsSpecs.def_options(__CALLER__.module, options, :element)
  end

  @doc """
  Defines that element exports a clock to pipeline.

  Exporting clock allows pipeline to choose it as the pipeline clock, enabling other
  elements to synchronize with it. Element's clock is accessible via `clock` field,
  while pipeline's one - via `parent_clock` field in callback contexts. Both of
  them can be used for starting timers.
  """
  defmacro def_clock(doc \\ "") do
    quote do
      @membrane_element_has_clock true

      Module.put_attribute(__MODULE__, :membrane_clock_moduledoc, """
      ## Clock

      This element provides a clock to its parent.

      #{unquote(doc)}
      """)

      @doc false
      @spec membrane_clock?() :: true
      def membrane_clock?, do: true
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    Membrane.Core.Child.generate_moduledoc(env.module, :element)
  end

  @doc """
  Brings common stuff needed to implement an element. Used by
  `Membrane.Source.__using__/1`, `Membrane.Filter.__using__/1`,
  `Membrane.Endpoint.__using__/1` and `Membrane.Sink.__using__/1`.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    bring_pad =
      if options |> Keyword.get(:bring_pad?, true) do
        quote do
          require Membrane.Pad
          alias Membrane.Pad
        end
      end

    quote location: :keep do
      @behaviour unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      alias Membrane.Element.CallbackContext, as: Ctx

      import unquote(__MODULE__), only: [def_clock: 0, def_clock: 1, def_options: 1]

      require Membrane.Core.Child.PadsSpecs

      Membrane.Core.Child.PadsSpecs.ensure_default_membrane_pads()

      unquote(bring_pad)

      @doc false
      @spec membrane_element?() :: true
      def membrane_element?, do: true

      @impl true
      def handle_init(_ctx, %_opt_struct{} = options),
        do: {[], options |> Map.from_struct()}

      @impl true
      def handle_init(_ctx, options), do: {[], options}

      @impl true
      def handle_setup(_context, state), do: {[], state}

      @impl true
      def handle_playing(_context, state), do: {[], state}

      @impl true
      def handle_info(_message, _context, state), do: {[], state}

      @impl true
      def handle_pad_added(_pad, _context, state), do: {[], state}

      @impl true
      def handle_pad_removed(_pad, _context, state), do: {[], state}

      @impl true
      def handle_event(_pad, _event, _context, state), do: {[], state}

      @impl true
      def handle_parent_notification(_notification, _ctx, state), do: {[], state}

      @impl true
      def handle_terminate_request(_ctx, state), do: {[terminate: :normal], state}

      defoverridable handle_init: 2,
                     handle_setup: 2,
                     handle_playing: 2,
                     handle_info: 3,
                     handle_pad_added: 3,
                     handle_pad_removed: 3,
                     handle_event: 4,
                     handle_parent_notification: 3,
                     handle_terminate_request: 2
    end
  end
end
