defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements in convenient way (actually elements should always be used inside
  a pipeline). Linking elements together enables them to pass data to one another,
  and process it in different ways.
  """

  alias Membrane.{
    CallbackError,
    Clock,
    Core,
    Element,
    Pad,
    PlaybackState,
    ParentSpec
  }

  alias Core.Parent
  alias Core.Message
  alias Core.Pipeline.State
  alias Parent.SpecController
  import Membrane.Helper.GenServer
  require Element
  require PlaybackState
  require Message
  require Pad
  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.CallbackHandler
  use GenServer

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @doc """
  Enables to check whether module is membrane pipeline
  """
  @callback membrane_pipeline? :: true

  @doc """
  Callback invoked on initialization of pipeline process. It should parse options
  and initialize element internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: pipeline_options_t) :: CallbackHandler.callback_return_t()

  @doc """
  Callback invoked when pipeline is shutting down.
  Internally called in `c:GenServer.terminate/2` callback.

  Useful for any cleanup required.
  """
  @callback handle_shutdown(reason, state :: State.internal_state_t()) :: :ok
            when reason: :normal | :shutdown | {:shutdown, any}

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
      debug("""
      Pipeline start link: module: #{inspect(module)},
      pipeline options: #{inspect(pipeline_options)},
      process options: #{inspect(process_options)}
      """)

      apply(GenServer, method, [__MODULE__, {module, pipeline_options}, process_options])
    else
      warn_error(
        """
        Cannot start pipeline, passed module #{inspect(module)} is not a Membrane Pipeline.
        Make sure that given module is the right one and it uses Membrane.Pipeline
        """,
        {:not_pipeline, module}
      )
    end
  end

  @doc """
  Changes pipeline's playback state to `:stopped` and terminates its process
  """
  @spec stop_and_terminate(pipeline :: pid) :: :ok
  def stop_and_terminate(pipeline) do
    Message.send(pipeline, :stop_and_terminate)
    :ok
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
    {:ok, clock} = Clock.start_link(proxy: true)
    state = %State{module: module, clock_proxy: clock}

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             __MODULE__,
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
    |> noreply(state)
  end

  @impl GenServer
  def terminate(reason, state) do
    :ok = state.module.handle_shutdown(reason, state.internal_state)
  end

  @impl CallbackHandler
  # Deprecation
  def handle_actions(%ParentSpec{} = spec, :handle_init, params, state) do
    warn("""
    Returning bare spec from `handle_init` is deprecated.
    Return `{{:ok, spec: spec}, state}` instead.
    Found in `#{inspect(state.module)}.handle_init/1`.
    """)

    super([spec: spec], :handle_init, params, state)
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, params, state) do
    super(actions, callback, params, state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, params, state) do
    with {:ok, state} <- do_handle_action(action, callback, params, state) do
      {:ok, state}
    else
      {{:error, :invalid_action}, state} ->
        raise CallbackError,
          kind: :invalid_action,
          action: action,
          callback: {state.module, callback}

      error ->
        error
    end
  end

  def do_handle_action({action, _args}, :handle_init, _params, state)
      when action not in [:spec] do
    {{:error, :invalid_action}, state}
  end

  def do_handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    Parent.Action.handle_forward(elementname, message, state)
  end

  def do_handle_action({:spec, spec = %ParentSpec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- SpecController.handle_spec(spec, state),
         do: {:ok, state}
  end

  def do_handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.Action.handle_remove_child(children, state)
  end

  def do_handle_action(_action, _callback, _params, state) do
    {{:error, :invalid_action}, state}
  end

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Parent
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

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
      @spec stop_and_terminate(pid) :: :ok
      defdelegate stop_and_terminate(pipeline), to: Pipeline

      @impl true
      def membrane_pipeline?, do: true

      @impl true
      def handle_init(_options), do: {{:ok, spec: %Membrane.ParentSpec{}}, %{}}

      @impl true
      def handle_notification(_notification, _from, state), do: {:ok, state}

      @impl true
      def handle_shutdown(_reason, _state), do: :ok

      defoverridable start: 0,
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
                     handle_notification: 3
    end
  end
end
