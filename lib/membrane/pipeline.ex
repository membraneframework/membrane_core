defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements and bins in convenient way (actually they should always be used inside
  a pipeline). Linking pipeline children together enables them to pass data to one
  another, and process it in different ways.

  To create a pipeline, use the `__using__/1` macro and implement callbacks
  of `Membrane.Pipeline` behaviour. For details on instantiating and linking
  children, see `Membrane.ChildrenSpec`.

  ## Starting and supervision

  Pipeline can be started with `start_link/2` or `start/2` functions. They both
  return `{:ok, supervisor_pid, pipeline_pid}` in case of success, because the pipeline
  is always spawned under a dedicated supervisor. The supervisor never restarts the
  pipeline, but it makes sure that the pipeline and its children terminate properly.
  If the pipeline needs to be restarted in case of failure, it should be spawned under
  another supervisor with a proper strategy.

  ### Starting under a supervision tree

  The pipeline can be spawned under a supervision tree like any `GenServer`. Also,
  `__using__/1` macro injects a `child_spec/1` function. A simple scenario can look like:

      defmodule MyPipeline do
        use Membrane.Pipeline

        def start_link(options) do
          Membrane.Pipeline.start_link(options, name: MyPipeline)
        end

        # ...
      end

      Supervisor.start_link([{MyPipeline, option: :value}], strategy: :one_for_one)
      send(MyPipeline, :message)

  ### Starting outside of a supervision tree

  When starting a pipeline outside a supervision tree and willing to interact with
  the pipeline by pid, `pipeline_pid` returned from `start_link` can be used, for example

      {:ok, _supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(MyPipeline, option: :value)
      send(pipeline_pid, :message)

  ### Visualizing pipeline's supervision tree

  Pipeline's internal supervision tree can be looked up with Applications tab of Erlang's Observer
  or with Livebook's `Kino` library.
  For debugging (and ONLY for debugging) purposes, you may use the following configuration:

        config :membrane_core, unsafely_name_processes_for_observer: [:components]

  that makes the observer's process tree graph more readable by naming pipeline's descendants, for example:
  ![Observer graph](assets/images/observer_graph.png).
  """

  use Bunch

  alias __MODULE__.{Action, CallbackContext}
  alias Membrane.{Child, Pad}
  alias Membrane.CrashGroup

  require Membrane.Logger
  require Membrane.Core.Message, as: Message

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/2` callback.
  """
  @type pipeline_options :: any

  @type name :: GenServer.name()

  @type config :: [config_entry()]
  @type config_entry :: {:name, name()}

  @type on_start ::
          {:ok, supervisor_pid :: pid, pipeline_pid :: pid}
          | {:error, {:already_started, pid()} | term()}

  @type state :: any()

  @typedoc """
  Defines return values from Pipeline callback functions.

  ## Return values

    * `{[action], state}` - Return a list of actions that will be performed within the
      pipeline. This can be used to start new children, or to send messages to specific children,
      for example. Actions are a tuple of `{type, arguments}`, so may be written in the
      form a keyword list. See `Membrane.Pipeline.Action` for more info.
  """
  @type callback_return_t ::
          {[Action.t()], state}

  @doc """
  Callback invoked on initialization of pipeline.

  This callback is synchronous: the process which started the pipeline waits until `handle_init`
  finishes. For that reason, it's important to do any long-lasting or complex work in `c:handle_setup/2`,
  while `handle_init` should be used for things like parsing options, initializing state or spawning
  children.
  """
  @callback handle_init(context :: CallbackContext.Init.t(), options :: pipeline_options) ::
              callback_return_t()

  @doc """
  Callback invoked when pipeline is requested to terminate with `terminate/2`.

  By default it returns `t:Membrane.Pipeline.Action.terminate_t/0` with reason `:normal`.
  """
  @callback handle_terminate_request(context :: CallbackContext.TerminateRequest.t(), state) ::
              callback_return_t()

  @doc """
  Callback invoked on pipeline startup, right after `c:handle_init/2`.

  Any long-lasting or complex initialization should happen here.
  """
  @callback handle_setup(
              context :: CallbackContext.Setup.t(),
              state
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline switches the playback to `:playing`.
  """
  @callback handle_playing(
              context :: CallbackContext.Playing.t(),
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
              context :: CallbackContext.Info.t(),
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
  Callback invoked when children of `Membrane.ChildrenSpec` are started.
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

  @optional_callbacks handle_init: 2,
                      handle_setup: 2,
                      handle_playing: 2,
                      handle_info: 3,
                      handle_spec_started: 3,
                      handle_element_start_of_stream: 4,
                      handle_element_end_of_stream: 4,
                      handle_child_notification: 4,
                      handle_tick: 3,
                      handle_crash_group_down: 3,
                      handle_call: 3,
                      handle_terminate_request: 2

  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's `c:handle_init/2` callback.
  Note that this function returns `{:ok, supervisor_pid, pipeline_pid}` in case of
  success. Check the 'Starting and supervision' section of the moduledoc for details.
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

      Membrane.Core.Pipeline.Supervisor.run(
        method,
        name,
        &GenServer.start_link(
          Membrane.Core.Pipeline,
          %{
            name: name,
            module: module,
            options: pipeline_options,
            subprocess_supervisor: &1
          },
          process_options
        )
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
  Gracefully terminates the pipeline.

  Accepts two options:
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
  # It was necessary, since delegating to the deprecated function led to a deprecation warning being printed once 'use Membrane.Pipeline' was done,
  # despite the fact that the deprecated function wasn't called. In the future releases we will remove deprecated functions and we will also remove that
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
                pipeline_options :: unquote(__MODULE__).pipeline_options(),
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
                pipeline_options :: unquote(__MODULE__).pipeline_options(),
                process_options :: GenServer.options()
              ) :: GenServer.on_start()
        def start(pipeline_options \\ nil, process_options \\ []) do
          unquote(__MODULE__).start(__MODULE__, pipeline_options, process_options)
        end
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:terminate, &1})) do
        @doc """
        Changes pipeline's playback to `:stopped` and terminates its process.
        """
        @spec terminate(pid, Keyword.t()) :: :ok
        defdelegate terminate(pipeline, opts \\ []), to: unquote(__MODULE__)
      end
    end
  end

  @doc """
  Brings all the stuff necessary to implement a pipeline.

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

      @doc false
      @spec membrane_pipeline?() :: true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_ctx, %_opt_struct{} = options),
        do: {[], options |> Map.from_struct()}

      @impl true
      def handle_init(_ctx, options), do: {[], options}

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
      def handle_child_notification(notification, element, _ctx, state), do: {[], state}

      @impl true
      def handle_crash_group_down(_group_name, _ctx, state), do: {[], state}

      @impl true
      def handle_call(message, _ctx, state), do: {[], state}

      @impl true
      def handle_terminate_request(_ctx, state), do: {[terminate: :normal], state}

      defoverridable child_spec: 1,
                     handle_init: 2,
                     handle_setup: 2,
                     handle_playing: 2,
                     handle_info: 3,
                     handle_spec_started: 3,
                     handle_element_start_of_stream: 4,
                     handle_element_end_of_stream: 4,
                     handle_child_notification: 4,
                     handle_crash_group_down: 3,
                     handle_call: 3,
                     handle_terminate_request: 2
    end
  end
end
