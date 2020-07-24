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
  use GenServer

  require Membrane.Logger
  require Membrane.Element

  alias Membrane.{Clock, Child, Core, Pad}
  alias Membrane.Core.{Parent, CallbackHandler, PlaybackHandler}
  alias Membrane.Core.Pipeline.State
  alias Membrane.Pipeline.CallbackContext

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @type state_t :: map | struct

  @type callback_return_t ::
          {:ok | {:ok, [Membrane.Parent.Action.t()]} | {:error, any}, state_t}
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
  @callback handle_init(options :: pipeline_options_t) :: CallbackHandler.callback_return_t()

  @doc """
  Callback invoked when pipeline is shutting down.
  Internally called in `c:GenServer.terminate/2` callback.

  Useful for any cleanup required.
  """
  @callback handle_shutdown(reason, state :: any) :: :ok
            when reason: :normal | :shutdown | {:shutdown, any}

  @doc """
  Callback invoked when pipeline transition from `:stopped` to `:prepared` state has finished,
  that is all of its children are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline transition from `:playing` to `:prepared` state has finished,
  that is all of its children are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_playing(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_stopped(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when pipeline is in `:terminating` state, i.e. all its children
  are in this state.
  """
  @callback handle_stopped_to_terminating(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Membrane.Notification.t(),
              element :: Child.name_t(),
              context :: CallbackContext.Notification.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(
              message :: any,
              context :: CallbackContext.Other.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when an element receives `Membrane.Event.StartOfStream` event.
  """
  @callback handle_element_start_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when an element receives `Membrane.Event.EndOfStream` event.
  """
  @callback handle_element_end_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.ParentSpec` is linked and in the same playback
  state as pipeline.

  This callback can be started from `c:handle_init/1` callback or as
  `t:Membrane.Core.Parent.Action.spec_action_t/0` action.
  """
  @callback handle_spec_started(
              children :: [Child.name_t()],
              context :: CallbackContext.SpecStarted.t(),
              state :: any
            ) :: callback_return_t

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

      apply(GenServer, method, [__MODULE__, {module, pipeline_options}, process_options])
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
  def stop_and_terminate(pipeline, opts \\ []) do
    blocking? = Keyword.get(opts, :blocking?, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    ref = if blocking?, do: Process.monitor(pipeline)

    PlaybackHandler.request_playback_state_change(pipeline, :terminating)

    if blocking?,
      do: wait_for_down(ref, timeout),
      else: :ok
  end

  defp wait_for_down(ref, timeout) do
    receive do
      {:DOWN, ^ref, _, _, _} ->
        :ok
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Changes playback state to `:playing`.

  An alias for `Membrane.Core.PlaybackHandler.change_playback_state/2` with proper state.
  """
  @spec play(pid) :: :ok
  def play(pid), do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :playing)

  @doc """
  Changes playback state to `:prepared`.

  An alias for `Membrane.Core.PlaybackHandler.change_playback_state/2` with proper state.
  """
  @spec prepare(pid) :: :ok
  def prepare(pid),
    do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :prepared)

  @doc """
  Changes playback state to `:stopped`.

  An alias for `Membrane.Core.PlaybackHandler.change_playback_state/2` with proper state.
  """
  @spec stop(pid) :: :ok
  def stop(pid), do: Membrane.Core.PlaybackHandler.request_playback_state_change(pid, :stopped)

  @impl GenServer
  def init(module) when is_atom(module) do
    init({module, module |> Bunch.Module.struct()})
  end

  def init(%module{} = pipeline_options) do
    init({module, pipeline_options})
  end

  def init({module, pipeline_options}) do
    pipeline_name = "pipeline@#{:erlang.pid_to_list(self())}"
    :ok = Membrane.Helper.LocationPath.set_current_path([pipeline_name])
    :ok = Membrane.Logger.set_prefix(pipeline_name)
    {:ok, clock} = Clock.start_link(proxy: true)
    state = %State{module: module, clock_proxy: clock}

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             Core.Pipeline.ActionHandler,
             %{state: false},
             [pipeline_options],
             state
           ) do
      {:ok, state}
    end
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_pipeline?)
  end

  @impl GenServer
  def handle_info(message, state) do
    Parent.MessageDispatcher.handle_message(message, state)
  end

  @impl GenServer
  def terminate(reason, state) do
    :ok = state.module.handle_shutdown(reason, state.internal_state)
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

    quote do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      unquote(bring_spec)
      unquote(bring_pad)

      @doc """
      Starts the pipeline `#{inspect(__MODULE__)}` and links it to the current process.

      A proxy for `Membrane.Pipeline.start_link/3`
      """
      @spec start_link(
              pipeline_options :: Pipeline.pipeline_options_t(),
              process_options :: GenServer.options()
            ) :: GenServer.on_start()
      def start_link(pipeline_options \\ nil, process_options \\ []) do
        Pipeline.start_link(__MODULE__, pipeline_options, process_options)
      end

      @doc """
      Starts the pipeline `#{inspect(__MODULE__)}` without linking it
      to the current process.

      A proxy for `Membrane.Pipeline.start/3`
      """
      @spec start(
              pipeline_options :: Pipeline.pipeline_options_t(),
              process_options :: GenServer.options()
            ) :: GenServer.on_start()
      def start(pipeline_options \\ nil, process_options \\ []) do
        Pipeline.start(__MODULE__, pipeline_options, process_options)
      end

      @doc """
      Changes playback state of pipeline to `:playing`

      A proxy for `Membrane.Pipeline.play/1`
      """
      @spec play(pid()) :: :ok
      defdelegate play(pipeline), to: Pipeline

      @doc """
      Changes playback state to `:prepared`.

      A proxy for `Membrane.Pipeline.prepare/1`
      """
      @spec prepare(pid) :: :ok
      defdelegate prepare(pipeline), to: Pipeline

      @doc """
      Changes playback state to `:stopped`.

      A proxy for `Membrane.Pipeline.stop/1`
      """
      @spec stop(pid) :: :ok
      defdelegate stop(pid), to: Pipeline

      @doc """
      Changes pipeline's playback state to `:stopped` and terminates its process.

      A proxy for `Membrane.Pipeline.stop_and_terminate/1`
      """
      @spec stop_and_terminate(pid, Keyword.t()) :: :ok
      defdelegate stop_and_terminate(pipeline, opts), to: Pipeline

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {{:ok, spec: %Membrane.ParentSpec{}}, %{}}

      @impl true
      def handle_shutdown(_reason, _state), do: :ok

      @impl true
      def handle_stopped_to_prepared(_ctx, state), do: handle_stopped_to_prepared(state)

      @impl true
      def handle_prepared_to_playing(_ctx, state), do: handle_prepared_to_playing(state)

      @impl true
      def handle_playing_to_prepared(_ctx, state), do: handle_playing_to_prepared(state)

      @impl true
      def handle_prepared_to_stopped(_ctx, state), do: handle_prepared_to_stopped(state)

      @impl true
      def handle_stopped_to_terminating(_ctx, state), do: handle_stopped_to_terminating(state)

      @impl true
      def handle_other(message, _ctx, state), do: handle_other(message, state)

      @impl true
      def handle_spec_started(new_children, _ctx, state),
        do: handle_spec_started(new_children, state)

      @impl true
      def handle_element_start_of_stream({element, pad}, _ctx, state),
        do: handle_element_start_of_stream({element, pad}, state)

      @impl true
      def handle_element_end_of_stream({element, pad}, _ctx, state),
        do: handle_element_end_of_stream({element, pad}, state)

      @impl true
      def handle_notification(notification, element, _ctx, state),
        do: handle_notification(notification, element, state)

      # DEPRECATED:

      @doc false
      def handle_stopped_to_prepared(state), do: {:ok, state}
      @doc false
      def handle_prepared_to_playing(state), do: {:ok, state}
      @doc false
      def handle_playing_to_prepared(state), do: {:ok, state}
      @doc false
      def handle_prepared_to_stopped(state), do: {:ok, state}
      @doc false
      def handle_stopped_to_terminating(state), do: {:ok, state}
      @doc false
      def handle_other(_message, state), do: {:ok, state}
      @doc false
      def handle_spec_started(_new_children, state), do: {:ok, state}
      @doc false
      def handle_element_start_of_stream({_element, _pad}, state), do: {:ok, state}
      @doc false
      def handle_element_end_of_stream({_element, _pad}, state), do: {:ok, state}
      @doc false
      def handle_notification(_notification, _element, state), do: {:ok, state}

      deprecated = [
        handle_stopped_to_prepared: 1,
        handle_prepared_to_playing: 1,
        handle_playing_to_prepared: 1,
        handle_prepared_to_stopped: 1,
        handle_stopped_to_terminating: 1,
        handle_other: 2,
        handle_spec_started: 2,
        handle_element_start_of_stream: 2,
        handle_element_end_of_stream: 2,
        handle_notification: 3
      ]

      defoverridable [
                       start: 0,
                       start: 1,
                       start: 2,
                       start_link: 0,
                       start_link: 1,
                       start_link: 2,
                       play: 1,
                       prepare: 1,
                       stop: 1,
                       handle_init: 1,
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
                       handle_notification: 4
                     ] ++ deprecated
    end
  end
end
