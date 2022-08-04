defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements and bins in convenient way (actually they should always be used inside
  a pipeline). Linking pipeline children together enables them to pass data to one
  another, and process it in different ways.

  To create a pipeline, use the `__using__/1` macro and implement callbacks
  of `Membrane.Pipeline` behaviour. For details on instantiating and linking
  children, see `Membrane.ParentSpec`.
  """

  use Bunch

  alias __MODULE__.{Action, CallbackContext}
  alias Membrane.{Child, Pad}
  alias Membrane.CrashGroup

  require Membrane.Logger
  require Membrane.Core.Message, as: Message

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options :: any

  @type name :: GenServer.name()

  @type config :: [name: name()]

  @type on_start ::
          {:ok, pipeline_pid :: pid, supervisor_pid :: pid}
          | {:error, {:already_started, pid()} | term()}

  @type state :: map | struct

  @typedoc """
  Defines return values from Pipeline callback functions.

  ## Return values

    * `{:ok, state}` - Save process state, with no actions to change the pipeline.
    * `{{:ok, [action]}, state}` - Return a list of actions that will be performed within the
      pipeline. This can be used to start new children, or to send messages to specific children,
      for example. Actions are a tuple of `{type, arguments}`, so may be written in the
      form a keyword list. See `Membrane.Pipeline.Action` for more info.
    * `{{:error, reason}, state}` - Terminates the pipeline with the given reason.
    * `{:error, reason}` - raises a `Membrane.CallbackError` with the error tuple.
  """
  @type callback_return_t ::
          {:ok | {:ok, [Action.t()]} | {:error, any}, state}
          | {:error, any}

  @doc """
  Enables to check whether module is membrane pipeline
  """
  @callback membrane_pipeline? :: true

  @doc """
  Callback invoked on initialization of pipeline process. It should parse options
  and initialize pipeline's internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: pipeline_options) :: callback_return_t()

  @doc """
  Callback invoked when pipeline is shutting down.
  Internally called in `c:GenServer.terminate/2` callback.

  Useful for any cleanup required.
  """
  @callback handle_terminate_yolo(reason, state) :: :ok
            when reason: :normal | :shutdown | {:shutdown, any} | term()

  @doc """
  Callback invoked when pipeline transition from `:stopped` to `:prepared` state has finished,
  that is all of its children are prepared to enter `:playing` state.
  """
  @callback handle_setup(
              context :: CallbackContext.PlaybackChange.t(),
              state
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_play(
              context :: CallbackContext.PlaybackChange.t(),
              state
            ) ::
              callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_child_notification(
              notification :: Membrane.ChildNotification.t(),
              element :: Child.name_t(),
              context :: CallbackContext.ChildNotification.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving data sent from NIFs or other stuff.
  """
  @callback handle_info(
              message :: any,
              context :: CallbackContext.Other.t(),
              state
            ) ::
              callback_return_t

  @doc """
  Callback invoked when a child element starts processing stream via given pad.
  """
  @callback handle_element_start_of_stream(
              child :: Child.name_t(),
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked when a child element finishes processing stream via given pad.
  """
  @callback handle_element_end_of_stream(
              child :: Child.name_t(),
              pad :: Pad.ref_t(),
              context :: CallbackContext.StreamManagement.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.ParentSpec` is linked and in the same playback
  state as pipeline.

  This callback can be started from `c:handle_init/1` callback or as
  `t:Membrane.Pipeline.Action.spec_t/0` action.
  """
  @callback handle_spec_started(
              children :: [Child.name_t()],
              context :: CallbackContext.SpecStarted.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked upon each timer tick. A timer can be started with `Membrane.Pipeline.Action.start_timer_t`
  action.
  """
  @callback handle_tick(
              timer_id :: any,
              context :: CallbackContext.Tick.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked when crash of the crash group happens.
  """
  @callback handle_crash_group_down(
              group_name :: CrashGroup.name_t(),
              context :: CallbackContext.CrashGroupDown.t(),
              state
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline is called using a synchronous call.
  """
  @callback handle_call(
              message :: any,
              context :: CallbackContext.Call.t(),
              state
            ) ::
              callback_return_t

  @optional_callbacks handle_init: 1,
                      handle_terminate_yolo: 2,
                      handle_setup: 2,
                      handle_play: 2,
                      handle_info: 3,
                      handle_spec_started: 3,
                      handle_element_start_of_stream: 4,
                      handle_element_end_of_stream: 4,
                      handle_child_notification: 4,
                      handle_tick: 3,
                      handle_crash_group_down: 3,
                      handle_call: 3

  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's `c:handle_init/1` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(module, pipeline_options, config) :: on_start
  def start_link(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start_link, module, pipeline_options, process_options)

  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, pipeline_options, config) :: on_start
  def start(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start, module, pipeline_options, process_options)

  defp do_start(method, module, pipeline_options, process_options) do
    if module |> pipeline? do
      Membrane.Logger.debug("""
      Pipeline start link: module: #{inspect(module)},
      pipeline options: #{inspect(pipeline_options)},
      process options: #{inspect(process_options)}
      """)

      name =
        case Keyword.fetch(process_options, :name) do
          {:ok, name} when is_atom(name) -> Atom.to_string(name)
          _other -> nil
        end
        |> case do
          "Elixir." <> module -> module
          name -> name
        end

      setup_observability = Membrane.Core.Observability.setup_fun(:pipeline, name)

      Membrane.Core.Parent.Supervisor.go_brrr(
        method,
        &GenServer.start_link(
          Membrane.Core.Pipeline,
          %{
            module: module,
            options: pipeline_options,
            setup_observability: setup_observability,
            children_supervisor: &1
          },
          process_options
        ),
        setup_observability
      )
    else
      Membrane.Logger.error("""
      Cannot start pipeline, passed module #{inspect(module)} is not a Membrane Pipeline.
      Make sure that given module is the right one and it uses Membrane.Pipeline
      """)

      {:error, {:not_pipeline, module}}
    end
  end

  @doc """
  Changes pipeline's playback state to `:stopped` and terminates its process.
  It accepts two options:
    * `blocking?` - tells whether to stop the pipeline synchronously
    * `timeout` - if `blocking?` is set to true it tells how much
      time (ms) to wait for pipeline to get terminated. Defaults to 5000.
  """
  @spec stop_and_terminate(pipeline :: pid, Keyword.t()) ::
          :ok | {:error, :timeout}
  @deprecated "use terminate/2 instead"
  def stop_and_terminate(pipeline, opts \\ []) do
    terminate(pipeline, opts)
  end

  @doc """
  Changes pipeline's playback state to `:stopped` and terminates its process.
  It accepts two options:
    * `blocking?` - tells whether to stop the pipeline synchronously
    * `timeout` - if `blocking?` is set to true it tells how much
      time (ms) to wait for pipeline to get terminated. Defaults to 5000.
  """
  @spec terminate(pipeline :: pid, Keyword.t()) ::
          :ok | {:error, :timeout}
  def terminate(pipeline, opts \\ []) do
    blocking? = Keyword.get(opts, :blocking?, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    ref = if blocking?, do: Process.monitor(pipeline)
    Message.send(pipeline, :terminate)

    if(blocking?,
      do: wait_for_down(ref, timeout),
      else: :ok
    )
  end

  @spec call(pid, any, integer()) :: :ok
  def call(pipeline, message, timeout \\ 5000) do
    GenServer.call(pipeline, message, timeout)
  end

  defp wait_for_down(ref, timeout) do
    receive do
      {:DOWN, ^ref, _process, _pid, _reason} ->
        :ok
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_pipeline?)
  end

  @doc false
  # Credo was disabled there, since it was complaining about too high CC of the following macro, which in fact does not look too complex.
  # The change which lead to CC increase was making the default definition of function call another function, instead of delegating to that function.
  # It was necessary, since delegating to the deprecated function led to a depracation warning being printed once 'use Membrane.Pipleine' was done,
  # despite the fact that the depreacted function wasn't called. In the future releases we will remove deprecated functions and we will also remove that
  # credo disable instruction so this can be seen just as a temporary solution.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __before_compile__(_env) do
    quote do
      unless Enum.any?(0..2, &Module.defines?(__MODULE__, {:start_link, &1})) do
        @doc """
        Starts the pipeline `#{inspect(__MODULE__)}` and links it to the current process.

        A proxy for `#{inspect(unquote(__MODULE__))}.start_link/3`
        """
        @spec start_link(
                pipeline_options :: unquote(__MODULE__).pipeline_options_t(),
                process_options :: GenServer.options()
              ) :: GenServer.on_start()
        def start_link(pipeline_options \\ nil, process_options \\ []) do
          unquote(__MODULE__).start_link(__MODULE__, pipeline_options, process_options)
        end
      end

      unless Enum.any?(0..2, &Module.defines?(__MODULE__, {:start, &1})) do
        @doc """
        Starts the pipeline `#{inspect(__MODULE__)}` without linking it
        to the current process.

        A proxy for `#{inspect(unquote(__MODULE__))}.start/3`
        """
        @spec start(
                pipeline_options :: unquote(__MODULE__).pipeline_options_t(),
                process_options :: GenServer.options()
              ) :: GenServer.on_start()
        def start(pipeline_options \\ nil, process_options \\ []) do
          unquote(__MODULE__).start(__MODULE__, pipeline_options, process_options)
        end
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:terminate, &1})) do
        @doc """
        Changes pipeline's playback state to `:stopped` and terminates its process.
        """
        @spec terminate(pid, Keyword.t()) :: :ok
        defdelegate terminate(pipeline, opts \\ []), to: unquote(__MODULE__)
      end
    end
  end

  @doc """
  Brings all the stuff necessary to implement a pipeline.

  Options:
    - `:bring_spec?` - if true (default) imports and aliases `Membrane.ParentSpec`
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    bring_spec =
      if options |> Keyword.get(:bring_spec?, true) do
        quote do
          import Membrane.ParentSpec
          alias Membrane.ParentSpec
        end
      end

    bring_pad =
      if options |> Keyword.get(:bring_pad?, true) do
        quote do
          require Membrane.Pad
          alias Membrane.Pad
        end
      end

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      @before_compile Pipeline

      unquote(bring_spec)
      unquote(bring_pad)

      @doc """
      Returns child specification for spawning under a supervisor
      """
      # credo:disable-for-next-line Credo.Check.Readability.Specs
      def child_spec(arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]},
          type: :supervisor
        }
      end

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {:ok, %{}}

      @impl true
      def handle_terminate_yolo(_reason, _state), do: :ok

      @impl true
      def handle_setup(_ctx, state), do: {:ok, state}

      @impl true
      def handle_play(_ctx, state), do: {:ok, state}

      @impl true
      def handle_info(message, _ctx, state), do: {:ok, state}

      @impl true
      def handle_spec_started(new_children, _ctx, state), do: {:ok, state}

      @impl true
      def handle_element_start_of_stream(_element, _pad, _ctx, state), do: {:ok, state}

      @impl true
      def handle_element_end_of_stream(_element, _pad, _ctx, state), do: {:ok, state}

      @impl true
      def handle_child_notification(notification, element, _ctx, state), do: {:ok, state}

      @impl true
      def handle_crash_group_down(_group_name, _ctx, state), do: {:ok, state}

      @impl true
      def handle_call(message, _ctx, state), do: {:ok, state}

      defoverridable child_spec: 1,
                     handle_init: 1,
                     handle_terminate_yolo: 2,
                     handle_setup: 2,
                     handle_play: 2,
                     handle_info: 3,
                     handle_spec_started: 3,
                     handle_element_start_of_stream: 4,
                     handle_element_end_of_stream: 4,
                     handle_child_notification: 4,
                     handle_crash_group_down: 3,
                     handle_call: 3
    end
  end
end
