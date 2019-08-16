defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.

  Pipelines are units that make it possible to instantiate, link and manage
  elements in convenient way (actually elements should always be used inside
  a pipeline). Linking elements together enables them to pass data to one another,
  and process it in different ways.
  """

  alias Membrane.Core.Pipeline.State
  alias Membrane.{CallbackError, Core, Element, Notification, Pad, Spec}
  alias Core.Message
  alias Core.Pipeline.SpecController
  alias Membrane.Core.Parent
  alias Parent.ChildrenController
  import Membrane.Helper.GenServer
  require Element
  require Membrane.PlaybackState
  require Message
  require Pad
  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.CallbackHandler
  use GenServer
  use Membrane.Core.PlaybackHandler

  @typedoc """
  Defines options that can be passed to `start/3` / `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type pipeline_options_t :: any

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t ::
          CallbackHandler.callback_return_t(Parent.Action.t(), State.internal_state_t())

  @doc """
  Enables to check whether module is membrane pipeline
  """
  @callback membrane_pipeline? :: true

  @doc """
  Callback invoked on initialization of pipeline process. It should parse options
  and initialize element internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: pipeline_options_t) ::
              {{:ok, Spec.t()}, State.internal_state_t()}
              | {:error, any}

  @doc """
  Callback invoked when pipeline transition from `:stopped` to `:prepared` state has finished,
  that is all of its elements are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline transition from `:playing` to `:prepared` state has finished,
  that is all of its elements are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_playing(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_stopped(state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Notification.t(),
              element :: ChildrenController.child_name_t(),
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(message :: any, state :: State.internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline's element receives start_of_stream event.
  """
  @callback handle_element_start_of_stream(
              {Element.name_t(), Pad.t()},
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline's element receives end_of_stream event.
  """
  @callback handle_element_end_of_stream(
              {Element.name_t(), Pad.t()},
              state :: State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.Pipeline.Spec` is linked and in the same playback
  state as pipeline.

  Spec can be started from `c:handle_init/1` callback or as `t:spec_action_t/0`
  action.
  """
  @callback handle_spec_started(
              elements :: [ChildrenController.child_name_t()],
              state :: State.internal_state_t()
            ) ::
              callback_return_t

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

  An alias for `change_playback_state/2` with proper state.
  """
  @spec play(pid) :: :ok
  def play(pid), do: change_playback_state(pid, :playing)

  @doc """
  Changes playback state to `:prepared`.

  An alias for `change_playback_state/2` with proper state.
  """
  @spec prepare(pid) :: :ok
  def prepare(pid), do: change_playback_state(pid, :prepared)

  @doc """
  Changes playback state to `:stopped`.

  An alias for `change_playback_state/2` with proper state.
  """
  @spec stop(pid) :: :ok
  def stop(pid), do: change_playback_state(pid, :stopped)

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  defp change_playback_state(pid, new_state)
       when Membrane.PlaybackState.is_playback_state(new_state) do
    alias Membrane.Core.Message
    require Message
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end

  @impl GenServer
  def init(module) when is_atom(module) do
    init({module, module |> Bunch.Module.struct()})
  end

  def init(%module{} = pipeline_options) do
    init({module, pipeline_options})
  end

  def init({module, pipeline_options}) do
    with {{:ok, spec}, internal_state} <- module.handle_init(pipeline_options) do
      state = %State{internal_state: internal_state, module: module}
      Message.self(:handle_spec, spec)
      {:ok, state}
    else
      {:error, reason} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason

      other ->
        raise CallbackError, kind: :bad_return, callback: {module, :handle_init}, value: other
    end
  end

  @doc """
  Checks whether module is a pipeline.
  """
  @spec pipeline?(module) :: boolean
  def pipeline?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_pipeline?)
  end

  @impl PlaybackHandler
  def handle_playback_state(_old, new, state) do
    children_pids = state |> Parent.ChildrenModel.get_children() |> Map.values()

    children_pids
    |> Enum.each(&change_playback_state(&1, new))

    state = %{state | pending_pids: children_pids |> MapSet.new()}
    PlaybackHandler.suspend_playback_change(state)
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(_old, :stopped, %State{terminating?: true} = state) do
    Message.self(:stop_and_terminate)
    {:ok, state}
  end

  def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

  @impl GenServer
  def handle_info(Message.new(cb, [element_name, pad_ref]), state)
      when cb in [:handle_start_of_stream, :handle_end_of_stream] do
    CallbackHandler.exec_and_handle_callback(
      to_parent_sm_callback(cb),
      __MODULE__,
      [{element_name, pad_ref}],
      state
    )
    |> noreply(state)
  end

  def handle_info(message, state) do
    Parent.MessageDispatcher.handle_message(message, state, handlers())
    |> noreply(state)
  end

  @impl GenServer
  def terminate(reason, state) do
    CallbackHandler.exec_and_handle_callback(:handle_shutdown, __MODULE__, [reason], state)
    :ok
  end

  @impl CallbackHandler
  def handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    Parent.Action.handle_forward(elementname, message, state)
  end

  def handle_action({:spec, spec = %Spec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- ChildrenController.handle_spec(SpecController, spec, state),
         do: {:ok, state}
  end

  def handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.Action.handle_remove_child(children, state)
  end

  def handle_action(action, callback, _params, state) do
    Parent.Action.handle_unknown_action(action, callback, state.module)
  end

  defp to_parent_sm_callback(:handle_start_of_stream), do: :handle_element_start_of_stream
  defp to_parent_sm_callback(:handle_end_of_stream), do: :handle_element_end_of_stream

  @spec handlers :: Parent.MessageDispatcher.handlers()
  defp handlers,
    do: %{
      action_handler: __MODULE__,
      playback_controller: __MODULE__,
      spec_controller: SpecController
    }

  defmacro __using__(_) do
    quote location: :keep do
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
      def handle_init(_options), do: {{:ok, %Membrane.Spec{}}, %{}}

      @impl true
      def handle_stopped_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(state), do: {:ok, state}

      @impl true
      def handle_notification(_notification, _from, state), do: {:ok, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_spec_started(_new_children, state), do: {:ok, state}

      @impl true
      def handle_shutdown(_reason, _state), do: :ok

      @impl true
      def handle_element_start_of_stream({_element, _pad}, state), do: {:ok, state}

      @impl true
      def handle_element_end_of_stream({_element, _pad}, state), do: {:ok, state}

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
                     handle_stopped_to_prepared: 1,
                     handle_playing_to_prepared: 1,
                     handle_prepared_to_playing: 1,
                     handle_prepared_to_stopped: 1,
                     handle_notification: 3,
                     handle_other: 2,
                     handle_spec_started: 2,
                     handle_shutdown: 2,
                     handle_element_start_of_stream: 2,
                     handle_element_end_of_stream: 2
    end
  end
end
