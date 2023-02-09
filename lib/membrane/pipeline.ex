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
  alias Membrane.Core.PlaybackHandler
  alias Membrane.CrashGroup

  require Membrane.Logger

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @type state_t :: map | struct

  @typedoc """
  Defines return values from Pipeline callback functions.

  ## Return values

    * `{:ok, state}` - Save process state, with no actions to change the pipeline.
    * `{{:ok, [action]}, state}` - Return a list of actions that will be performed within the
      pipline. This can be used to start new children, or to send messages to specific children,
      for example. Actions are a tuple of `{type, arguments}`, so may be written in the
      form a keyword list. See `Membrane.Pipeline.Action` for more info.
    * `{{:error, reason}, state}` - Terminates the pipeline with the given reason.
    * `{:error, reason}` - raises a `Membrane.CallbackError` with the error tuple.
  """
  @type callback_return_t ::
          {:ok | {:ok, [Action.t()]} | {:error, any}, state_t}
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
  @callback handle_init(options :: pipeline_options_t) :: callback_return_t()

  @doc """
  Callback invoked when pipeline is shutting down.
  Internally called in `c:GenServer.terminate/2` callback.

  Useful for any cleanup required.
  """
  @callback handle_shutdown(reason, state :: state_t) :: :ok
            when reason: :normal | :shutdown | {:shutdown, any} | term()

  @doc """
  Callback invoked when pipeline transition from `:stopped` to `:prepared` state has finished,
  that is all of its children are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline transition from `:playing` to `:prepared` state has finished,
  that is all of its children are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_playing(
              context :: CallbackContext.PlaybackChange.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_stopped(
              context :: CallbackContext.PlaybackChange.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:terminating` state, i.e. all its children
  are in this state.
  """
  @callback handle_stopped_to_terminating(
              context :: CallbackContext.PlaybackChange.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Membrane.Notification.t(),
              element :: Child.name_t(),
              context :: CallbackContext.Notification.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving data sent from NIFs or other stuff.
  """
  @callback handle_other(
              message :: any,
              context :: CallbackContext.Other.t(),
              state :: state_t
            ) ::
              callback_return_t

  @doc """
  Callback invoked when a child element starts processing stream via given pad.
  """
  @callback handle_element_start_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when a child element finishes processing stream via given pad.
  """
  @callback handle_element_end_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: state_t
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
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked upon each timer tick. A timer can be started with `Membrane.Pipeline.Action.start_timer_t`
  action.
  """
  @callback handle_tick(
              timer_id :: any,
              context :: CallbackContext.Tick.t(),
              state :: state_t
            ) :: callback_return_t

  @doc """
  Callback invoked when crash of the crash group happens.
  """
  @callback handle_crash_group_down(
              group_name :: CrashGroup.name_t(),
              context :: CallbackContext.CrashGroupDown.t(),
              state :: state_t
            ) :: callback_return_t

  @optional_callbacks handle_init: 1,
                      handle_shutdown: 2,
                      handle_stopped_to_prepared: 2,
                      handle_playing_to_prepared: 2,
                      handle_prepared_to_playing: 2,
                      handle_prepared_to_stopped: 2,
                      handle_stopped_to_terminating: 2,
                      handle_other: 3,
                      handle_spec_started: 3,
                      handle_element_start_of_stream: 3,
                      handle_element_end_of_stream: 3,
                      handle_notification: 4,
                      handle_tick: 3,
                      handle_crash_group_down: 3

  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's `c:handle_init/1` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(
          module,
          pipeline_options :: pipeline_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start_link(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start_link, module, pipeline_options, process_options)

  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(
          module,
          pipeline_options :: pipeline_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start(module, pipeline_options \\ nil, process_options \\ []),
    do: do_start(:start, module, pipeline_options, process_options)

  defp do_start(method, module, pipeline_options, process_options) do
    if module |> pipeline? do
      Membrane.Logger.debug("""
      Pipeline start link: module: #{inspect(module)},
      pipeline options: #{inspect(pipeline_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [
        Membrane.Core.Pipeline,
        {module, pipeline_options},
        process_options
      ])
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
  It accpets two options:
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
  It accpets two options:
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

    PlaybackHandler.request_playback_state_change(pipeline, :terminating)

    if blocking?,
      do: wait_for_down(ref, timeout),
      else: :ok
  end

  @doc """
  Brutally exits pipeline process with all descendant components.
  It accpets two options:
    * `blocking?` - tells whether to wait, untill all killed processed are
      down. Defaluts to `false`.
    * `timeout` - if `blocking?` is set to true it tells how much
      time (ms) to wait for components to exit. Defaults to 5000.
  """
  @spec kill(pipeline :: pid, blocking?: true, timeout: timeout()) :: :ok | :error
  def kill(pipeline, opts \\ []) do
    blocking? = Keyword.get(opts, :blocking?, false)
    timeout = Keyword.get(opts, :timeout, 5_000)
    do_kill(pipeline, blocking?, timeout)
  end

  defp do_kill(pipeline, false, _timeout) do
    Membrane.Core.Registry.kill_pipeline_descendants(pipeline)
  end

  defp do_kill(pipeline, true, timeout) do
    monitors = Membrane.Core.Registry.monitor_pipeline_descendants(pipeline)
    Membrane.Core.Registry.kill_pipeline_descendants(pipeline)

    Enum.any?(monitors, fn ref ->
      receive do
        {:DOWN, ^ref, :process, _pid, _reason} -> false
      after
        timeout -> true
      end
    end)
    |> case do
      false -> :ok
      true -> :error
    end
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
  Changes playback state to `:playing`.
  """
  @spec play(pid) :: :ok
  @deprecated "use pipeline's :playback action instead"
  def play(pid), do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :playing)

  @doc """
  Changes playback state to `:prepared`.
  """
  @spec prepare(pid) :: :ok
  @deprecated "use pipeline's :playback action instead"
  def prepare(pid),
    do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :prepared)

  @doc """
  Changes playback state to `:stopped`.
  """
  @spec stop(pid) :: :ok
  @deprecated "use pipeline's :playback action instead"
  def stop(pid), do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :stopped)

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

      unless Module.defines?(__MODULE__, {:play, 1}) do
        @doc """
        Changes playback state of pipeline to `:playing`.
        """
        @spec play(pid()) :: :ok
        @deprecated "use pipeline's :playback action instead"
        def play(pid),
          do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :playing)
      end

      unless Module.defines?(__MODULE__, {:prepare, 1}) do
        @doc """
        Changes playback state to `:prepared`.
        """
        @spec prepare(pid()) :: :ok
        @deprecated "use pipeline's :playback action instead"
        def prepare(pid),
          do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :prepared)
      end

      unless Module.defines?(__MODULE__, {:stop, 1}) do
        @doc """
        Changes playback state to `:stopped`.
        """
        @spec stop(pid()) :: :ok
        @deprecated "use pipeline's :playback action instead"
        def stop(pid),
          do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :stopped)
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:terminate, &1})) do
        @doc """
        Changes pipeline's playback state to `:stopped` and terminates its process.
        """
        @spec terminate(pid, Keyword.t()) :: :ok
        defdelegate terminate(pipeline, opts \\ []), to: unquote(__MODULE__)
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:kill, &1})) do
        @doc """
        Brutally exits pipeline process with all descendant components.
        """
        @spec kill(pid, Keyword.t()) :: :ok
        defdelegate kill(pipeline, opts \\ []), to: unquote(__MODULE__)
      end

      unless Enum.any?(1..2, &Module.defines?(__MODULE__, {:stop_and_terminate, &1})) do
        @doc """
        Changes pipeline's playback state to `:stopped` and terminates its process.
        """
        @spec stop_and_terminate(pid, Keyword.t()) :: :ok
        @deprecated "use terminate/2 instead"
        def stop_and_terminate(pipeline, opts \\ []),
          do: Membrane.Pipeline.terminate(pipeline, opts)
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

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {:ok, %{}}

      @impl true
      def handle_shutdown(_reason, _state), do: :ok

      @impl true
      def handle_stopped_to_prepared(_ctx, state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(_ctx, state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(_ctx, state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(_ctx, state), do: {:ok, state}

      @impl true
      def handle_stopped_to_terminating(_ctx, state), do: {:ok, state}

      @impl true
      def handle_other(message, _ctx, state), do: {:ok, state}

      @impl true
      def handle_spec_started(new_children, _ctx, state), do: {:ok, state}

      @impl true
      def handle_element_start_of_stream({element, pad}, _ctx, state), do: {:ok, state}

      @impl true
      def handle_element_end_of_stream({element, pad}, _ctx, state), do: {:ok, state}

      @impl true
      def handle_notification(notification, element, _ctx, state), do: {:ok, state}

      @impl true
      def handle_crash_group_down(_group_name, _ctx, state), do: {:ok, state}

      defoverridable handle_init: 1,
                     handle_shutdown: 2,
                     handle_stopped_to_prepared: 2,
                     handle_playing_to_prepared: 2,
                     handle_prepared_to_playing: 2,
                     handle_prepared_to_stopped: 2,
                     handle_stopped_to_terminating: 2,
                     handle_other: 3,
                     handle_spec_started: 3,
                     handle_element_start_of_stream: 3,
                     handle_element_end_of_stream: 3,
                     handle_notification: 4,
                     handle_crash_group_down: 3
    end
  end
end
