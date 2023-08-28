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
          Membrane.Pipeline.start_link(__MODULE__, options, name: MyPipeline)
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

  Pipeline's internal supervision tree can be looked up with Applications tab of Erlang's Stalker
  or with Livebook's `Kino` library.
  For debugging (and ONLY for debugging) purposes, you may use the following configuration:

        config :membrane_core, unsafely_name_processes_for_stalker: [:components]

  that makes the stalker's process tree graph more readable by naming pipeline's descendants, for example:
  ![Stalker graph](assets/images/stalker_graph.png).
  """

  use Bunch

  alias __MODULE__.{Action, CallbackContext}
  alias Membrane.{Child, Pad, PipelineError}

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
  @type callback_return ::
          {[Action.t()], state}

  @doc """
  Callback invoked on initialization of pipeline.

  This callback is synchronous: the process which started the pipeline waits until `handle_init`
  finishes. For that reason, it's important to do any long-lasting or complex work in `c:handle_setup/2`,
  while `handle_init` should be used for things like parsing options, initializing state or spawning
  children.
  By default, it converts the `opts` to a map if they're a struct and sets them as the pipeline state.
  """
  @callback handle_init(context :: CallbackContext.t(), options :: pipeline_options) ::
              callback_return()

  @doc """
  Callback invoked when pipeline is requested to terminate with `terminate/2`.

  By default, it returns `t:Membrane.Pipeline.Action.terminate/0` with reason `:normal`.
  """
  @callback handle_terminate_request(context :: CallbackContext.t(), state) ::
              callback_return()

  @doc """
  Callback invoked on pipeline startup, right after `c:handle_init/2`.

  Any long-lasting or complex initialization should happen here.
  By default, it does nothing.
  """
  @callback handle_setup(
              context :: CallbackContext.t(),
              state
            ) ::
              callback_return

  @doc """
  Callback invoked when pipeline switches the playback to `:playing`.
  By default, it does nothing.
  """
  @callback handle_playing(
              context :: CallbackContext.t(),
              state
            ) ::
              callback_return

  @doc """
  Callback invoked when a child removes its pad.

  The callback won't be invoked, when you have initiated the pad removal,
  eg. when you have returned `t:Membrane.Pipeline.Action.remove_link()`
  action which made one of your children's pads be removed.
  By default, it does nothing.
  """
  @callback handle_child_pad_removed(
              child :: Child.name(),
              pad :: Pad.ref(),
              context :: CallbackContext.t(),
              state :: state
            ) :: callback_return

  @doc """
  Callback invoked when a notification comes in from a child.

  By default, it ignores the notification.
  """
  @callback handle_child_notification(
              notification :: Membrane.ChildNotification.t(),
              element :: Child.name(),
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving data sent from NIFs or other stuff.
  By default, it ignores the received message.
  """
  @callback handle_info(
              message :: any,
              context :: CallbackContext.t(),
              state
            ) ::
              callback_return

  @doc """
  Callback invoked when a child element starts processing stream via given pad.

  By default, it does nothing.
  """
  @callback handle_element_start_of_stream(
              child :: Child.name(),
              pad :: Pad.ref(),
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked when a child element finishes processing stream via given pad.

  By default, it does nothing.
  """
  @callback handle_element_end_of_stream(
              child :: Child.name(),
              pad :: Pad.ref(),
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked when children of `Membrane.ChildrenSpec` are started.

  By default, it does nothing.
  """
  @callback handle_spec_started(
              children :: [Child.name()],
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked upon each timer tick. A timer can be started with `Membrane.Pipeline.Action.start_timer`
  action.
  """
  @callback handle_tick(
              timer_id :: any,
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked when crash of the crash group happens.

  Context passed to this callback contains 2 additional fields: `:members` and `:crash_initiator`.
  By default, it does nothing.
  """
  @callback handle_crash_group_down(
              group_name :: Child.group(),
              context :: CallbackContext.t(),
              state
            ) :: callback_return

  @doc """
  Callback invoked when pipeline is called using a synchronous call.

  Context passed to this callback contains additional field `:from`.
  By default, it does nothing.
  """
  @callback handle_call(
              message :: any,
              context :: CallbackContext.t(),
              state
            ) ::
              callback_return

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
                      handle_terminate_request: 2,
                      handle_child_pad_removed: 4

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
  Terminates the pipeline.

  Accepts three options:
    * `asynchronous?` - if set to `true`, pipline termination won't be blocking and
      will be executed in the process, which pid is returned as function result. If
      set to `false`, pipeline termination will be blocking and will be executed in
      the process that called this function. Defaults to `false`.
    * `timeout` - tells how much time (ms) to wait for pipeline to get gracefully
      terminated. Defaults to 5000.
    * `force?` - if set to `true` and pipeline is still alive after `timeout`,
      pipeline will be killed using `Process.exit/2` with reason `:kill`, and function
      will return `{:error, :timeout}`. If set to `false` and pipeline is still alive
      after `timeout`, function will raise an error. Defaults to `false`.

  Returns:
    * `{:ok, pid}` - if option `asynchronous?: true` was passed.
    * `:ok` - if pipeline was gracefully terminated within `timeout`.
    * `{:error, :timeout}` - if pipeline was killed after a `timeout`.
  """
  @spec terminate(pipeline :: pid,
          timeout: timeout(),
          force?: boolean(),
          asynchronous?: boolean()
        ) ::
          :ok | {:ok, pid()} | {:error, :timeout}
  def terminate(pipeline, opts \\ []) do
    [asynchronous?: asynchronous?] ++ opts =
      Keyword.validate!(opts,
        asynchronous?: false,
        force?: false,
        timeout: 5000
      )
      |> Enum.sort()

    if asynchronous? do
      Task.start(__MODULE__, :do_terminate, [pipeline, opts])
    else
      do_terminate(pipeline, opts)
    end
  end

  @doc false
  @spec do_terminate(pipeline :: pid, timeout: timeout(), force?: boolean()) ::
          :ok | {:error, :timeout}
  def do_terminate(pipeline, opts) do
    timeout = Keyword.get(opts, :timeout)
    force? = Keyword.get(opts, :force?)

    ref = Process.monitor(pipeline)
    Message.send(pipeline, :terminate)

    receive do
      {:DOWN, ^ref, _process, _pid, _reason} ->
        :ok
    after
      timeout ->
        if force? do
          Process.exit(pipeline, :kill)
          {:error, :timeout}
        else
          raise PipelineError, """
          Pipeline #{inspect(pipeline)} hasn't terminated within given timeout (#{inspect(timeout)} ms).
          If you want to kill it anyway, use `force?: true` option.
          """
        end
    end
  end

  @spec call(pid, any, timeout()) :: term()
  def call(pipeline, message, timeout \\ 5000) do
    GenServer.call(pipeline, message, timeout)
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_pipeline?)
  end

  @doc """
  Lists PIDs of all the pipelines currently running on the current node.

  Use only for debugging purposes.
  """
  @spec list_pipelines() :: [pid]
  def list_pipelines() do
    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} -> List.keyfind(dictionary, :__membrane_pipeline__, 0)
        nil -> false
      end
    end)
  end

  @doc """
  Like `list_pipelines/0`, but allows to pass a node.
  """
  @spec list_pipelines(node()) :: [pid]
  def list_pipelines(node) do
    :erpc.call(node, __MODULE__, :list_pipelines, [])
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      unless Enum.any?(0..2, &Module.defines?(__MODULE__, {:start_link, &1})) do
        @doc """
        Starts the pipeline `#{inspect(__MODULE__)}` and links it to the current process.

        A proxy for `#{inspect(unquote(__MODULE__))}.start_link/3`
        """
        @spec start_link(
                unquote(__MODULE__).pipeline_options(),
                unquote(__MODULE__).config()
              ) :: unquote(__MODULE__).on_start()
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
                unquote(__MODULE__).pipeline_options(),
                unquote(__MODULE__).config()
              ) :: unquote(__MODULE__).on_start()
        def start(pipeline_options \\ nil, process_options \\ []) do
          unquote(__MODULE__).start(__MODULE__, pipeline_options, process_options)
        end
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:terminate, &1})) do
        @doc """
        Changes pipeline's playback to `:stopped` and terminates its process.
        """
        @spec terminate(pid, Keyword.t()) :: :ok | {:ok, pid()} | {:error, :timeout}
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
      if Keyword.get(options, :bring_spec?, true) do
        quote do
          import Membrane.ChildrenSpec
          alias Membrane.ChildrenSpec
        end
      end

    bring_pad =
      if Keyword.get(options, :bring_pad?, true) do
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
