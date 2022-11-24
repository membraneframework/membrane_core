defmodule Membrane.Bin do
  @moduledoc """
  Bins, similarly to pipelines, are containers for elements.
  However, at the same time, they can be placed and linked within pipelines.
  Although bin is a separate Membrane entity, it can be perceived as a pipeline within an element.
  Bins can also be nested within one another.

  There are two main reasons why bins are useful:
  * they enable creating reusable element groups
  * they allow managing their children, for instance by dynamically spawning or replacing them as the stream changes.

  In order to create bin `use Membrane.Bin` in your callback module.
  """

  alias __MODULE__.{Action, CallbackContext}
  alias Membrane.{Child, Pad}
  alias Membrane.Core.Child.PadsSpecs
  alias Membrane.Core.OptionsSpecs

  require Membrane.Core.Message
  require Membrane.Logger

  @type state_t :: any()

  @type callback_return_t :: {[Action.t()], state_t()}

  @typedoc """
  Defines options that can be passed to `start_link/3` and received
  in `c:handle_init/2` callback.
  """
  @type options_t :: struct | nil

  @typedoc """
  Type that defines a bin name by which it is identified.
  """
  @type name_t :: tuple() | atom()

  @doc """
  Callback invoked on initialization of bin.

  This callback is synchronous: the parent waits until it finishes. Also, any failures
  that happen in this callback crash the parent as well, regardless of crash groups.
  For these reasons, it's important to do any long-lasting or complex work in `c:handle_setup/2`,
  while `handle_init` should be used for things like parsing options, initializing state or
  spawning children.
  """
  @callback handle_init(context :: CallbackContext.Init.t(), options :: options_t) ::
              callback_return_t()

  @doc """
  Callback that is called when new pad has been added to bin. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_added(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadAdded.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback that is called when some pad of the bin has been removed. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_removed(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadRemoved.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked on bin startup, right after `c:handle_init/2`.

  Any long-lasting or complex initialization should happen here.
  """
  @callback handle_setup(
              context :: CallbackContext.Setup.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when bin switches the playback to `:playing`.
  """
  @callback handle_playing(
              context :: CallbackContext.Playing.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_child_notification(
              notification :: Membrane.ChildNotification.t(),
              element :: Child.name_t(),
              context :: CallbackContext.ChildNotification.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an parent.
  """
  @callback handle_parent_notification(
              notification :: Membrane.ParentNotification.t(),
              context :: CallbackContext.ParentNotification.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when bin receives a message that is not recognized
  as an internal membrane message.

  Can be used for receiving data from non-membrane processes.
  """
  @callback handle_info(
              message :: any,
              context :: CallbackContext.Info.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when a child element starts processing stream via given pad.
  """
  @callback handle_element_start_of_stream(
              child :: Child.name_t(),
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when a child element finishes processing stream via given pad.
  """
  @callback handle_element_end_of_stream(
              child :: Child.name_t(),
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when children of `Membrane.ChildrenSpec` are started.
  """
  @callback handle_spec_started(
              children :: [Child.name_t()],
              context :: CallbackContext.SpecStarted.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked upon each timer tick. A timer can be started with `t:Membrane.Bin.Action.start_timer_t/0`
  action.
  """
  @callback handle_tick(
              timer_id :: any,
              context :: CallbackContext.Tick.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  A callback invoked when the bin is being removed by its parent.

  By default it returns `t:Membrane.Bin.Action.terminate_t/0` with reason `:normal`.
  """
  @callback handle_terminate_request(context :: CallbackContext.TerminateRequest.t(), state_t) ::
              callback_return_t()

  @optional_callbacks handle_init: 2,
                      handle_pad_added: 3,
                      handle_pad_removed: 3,
                      handle_setup: 2,
                      handle_playing: 2,
                      handle_info: 3,
                      handle_spec_started: 3,
                      handle_element_start_of_stream: 4,
                      handle_element_end_of_stream: 4,
                      handle_child_notification: 4,
                      handle_parent_notification: 3,
                      handle_tick: 3,
                      handle_terminate_request: 2

  @doc PadsSpecs.def_pad_docs(:input, :bin)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_pad(name, :input, spec, :bin)
  end

  @doc PadsSpecs.def_pad_docs(:output, :bin)
  defmacro def_output_pad(name, spec) do
    PadsSpecs.def_pad(name, :output, spec, :bin)
  end

  @doc """
  Defines that bin exposes a clock which is a proxy to one of its children.

  If this macro is not called, no ticks will be forwarded to parent, regardless
  of clock definitions in its children.
  """
  defmacro def_clock(doc \\ "") do
    quote do
      @membrane_bin_exposes_clock true

      Module.put_attribute(__MODULE__, :membrane_clock_moduledoc, """
      ## Clock

      This bin exposes a clock of one of its children.

      #{unquote(doc)}
      """)

      @doc false
      @spec membrane_clock?() :: true
      def membrane_clock?, do: true
    end
  end

  @doc """
  Checks whether module is a bin.
  """
  @spec bin?(module) :: boolean
  def bin?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_bin?)
  end

  @doc """
  Macro defining options that parametrize bin.

  It automatically generates appropriate struct and documentation.

  #{OptionsSpecs.options_doc()}
  """
  defmacro def_options(options) do
    OptionsSpecs.def_options(__CALLER__.module, options, :bin)
  end

  @doc false
  defmacro __before_compile__(env) do
    Membrane.Core.Child.generate_moduledoc(env.module, :bin)
  end

  @doc """
  Brings all the stuff necessary to implement a bin.

  Options:
    - `:bring_spec?` - if true (default) imports and aliases `Membrane.ChildrenSpec`
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    bring_spec =
      if options |> Keyword.get(:bring_spec?, true) do
        quote do
          import Membrane.ChildrenSpec
          alias Membrane.ChildrenSpec
        end
      end

    bring_pad =
      if options |> Keyword.get(:bring_pad?, true) do
        quote do
          require Membrane.Pad
          alias Membrane.Pad
        end
      end

    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      unquote(bring_spec)
      unquote(bring_pad)

      import unquote(__MODULE__),
        only: [def_input_pad: 2, def_output_pad: 2, def_options: 1, def_clock: 0, def_clock: 1]

      require Membrane.Core.Child.PadsSpecs

      Membrane.Core.Child.PadsSpecs.ensure_default_membrane_pads()

      @doc false
      @spec membrane_bin?() :: true
      def membrane_bin?, do: true

      @impl true
      def handle_init(_ctx, %_opt_struct{} = options),
        do: {[], options |> Map.from_struct()}

      @impl true
      def handle_init(_ctx, options), do: {[], options}

      @impl true
      def handle_pad_added(_pad, _ctx, state), do: {[], state}

      @impl true
      def handle_pad_removed(_pad, _ctx, state), do: {[], state}

      @impl true
      def handle_setup(_ctx, state), do: {[], state}

      @impl true
      def handle_playing(_ctx, state), do: {[], state}

      @impl true
      def handle_info(message, _ctx, state), do: {[], state}

      @impl true
      def handle_spec_started(new_children, _ctx, state), do: {[], state}

      @impl true
      def handle_element_start_of_stream(_element, _pad, _ctx, state), do: {[], state}

      @impl true
      def handle_element_end_of_stream(_element, _pad, _ctx, state), do: {[], state}

      @impl true
      def handle_child_notification(_notification, _element, _ctx, state), do: {[], state}

      @impl true
      def handle_parent_notification(_notification, _ctx, state), do: {[], state}

      @impl true
      def handle_terminate_request(_ctx, state), do: {[terminate: :normal], state}

      defoverridable handle_init: 2,
                     handle_pad_added: 3,
                     handle_pad_removed: 3,
                     handle_setup: 2,
                     handle_playing: 2,
                     handle_info: 3,
                     handle_spec_started: 3,
                     handle_element_start_of_stream: 4,
                     handle_element_end_of_stream: 4,
                     handle_child_notification: 4,
                     handle_parent_notification: 3,
                     handle_terminate_request: 2
    end
  end

  defguard is_bin_name?(arg) when is_atom(arg) or is_tuple(arg)
end
