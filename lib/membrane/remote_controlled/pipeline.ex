defmodule Membrane.RemoteControlled.Pipeline do
  @moduledoc """
  `Membrane.RemoteControlled.Pipeline` is a basic `Membrane.Pipeline` implementation that can be
  controlled by a controlling process. The controlling process can request the execution of arbitrary
  valid `Membrane.Pipeline.Action`. The controlling process can also subscribe and await for certain
  events that are emitted by the pipeline. `Membrane.RemoteControlled.Pipeline` can be used when
  there is no need for introducing a custom logic in the `Membrane.Pipeline` callbacks implementation.
  An example of usage could be running a pipeline from the elixir script.
  Membrane.RemoteControlled.Pipeline emits the following events:
  * `{:playback_state, Membrane.PlaybackState.t()}` emitted when pipeline enters
  a given playback state,
  * `{:start_of_stream | :end_of_stream, Membrane.Element.name_t(), Membrane.Pad.name_t()}` emitted
  when one of direct pipeline children informs the pipeline about start or end of stream,
  * `{:notification, Membrane.Element.name_t(), Membrane.Notification.t()}` emitted when pipeline
  receives notification from one of its children.
  """

  use Membrane.Pipeline

  alias Membrane.Pipeline

  @type event_t ::
          {:playback_state, Membrane.PlaybackState.t()}
          | {:start_of_stream | :end_of_stream, Membrane.Element.name_t(), Membrane.Pad.name_t()}
          | {:notification, Membrane.Element.name_t(), Membrane.Notification.t()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:controller_pid]
    defstruct @enforce_keys ++ [matching_functions: []]
  end

  @doc """
  Starts the `Membrane.RemoteControlled.Pipeline` and links it to the current process. The process
  that makes the call to the `start_link/1` automatically become the controller process.
  """
  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(process_options \\ []) do
    args = [__MODULE__, %{controller_pid: self()}, process_options]
    apply(Pipeline, :start_link, args)
  end

  @doc """
  Does the same as the `start_link/1` but starts the process outside of the supervision tree.
  """
  @spec start(GenServer.options()) :: GenServer.on_start()
  def start(process_options \\ []) do
    args = [__MODULE__, %{controller_pid: self()}, process_options]
    apply(Pipeline, :start, args)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Pipeline.event_t()` that matches the given `pattern`.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` before awaiting
  any events. `pattern` has to be a match pattern.
  """
  defmacro await(pattern) do
    quote do
      unquote(pattern) =
        receive do
          unquote(pattern) = msg ->
            msg
        end
    end
  end

  @doc """
  Subscribes to a given `subscription_pattern`.
  The `subscription_pattern` must be a match pattern.

      subscribe(pid, {:playback_state, _})

  Such call would make the `Membrane.RemoteControlled.Pipeline` to send all `:playback_state` events to the
  controlling process.
  """
  defmacro subscribe(pipeline, subscription_pattern) do
    quote do
      send(
        unquote(pipeline),
        {:subscription, fn x -> match?(unquote(subscription_pattern), x) end}
      )
    end
  end

  @doc """
  Sends a list of `Pipeline.Action.t()` to the given `Membrane.RemoteControlled.Pipeline` for execution.

      children = ...
      links = ...
      actions = [{:spec, %ParentSpec{children: children, links: links}}]
      Pipeline.exec_actions(pipeline, actions)

  Such a call would make the `Membrane.RemoteControlled.Pipeline` to start the `Membrane.ParentSpec`
  specified in the action.
  """
  @spec exec_actions(pid(), [Pipeline.Action.t()]) :: :ok
  def exec_actions(pipeline, actions) do
    send(pipeline, {:exec_actions, actions})
    :ok
  end

  @impl true
  def handle_init(opts) do
    %{controller_pid: controller_pid} = opts

    state = %State{controller_pid: controller_pid}
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    pipeline_event = {:playback_state, :prepared}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    pipeline_event = {:playback_state, :playing}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    pipeline_event = {:playback_state, :stopped}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    pipeline_event = {:playback_state, :prepared}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_stopped_to_terminating(_ctx, state) do
    pipeline_event = {:playback_state, :terminating}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = {:end_of_stream, element_name, pad_ref}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_element_start_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = {:start_of_stream, element_name, pad_ref}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_notification(notification, element, _ctx, state) do
    pipeline_event = {:notification, element, notification}
    maybe_send_event_to_controller(pipeline_event, state)

    {:ok, state}
  end

  @impl true
  def handle_other({:exec_actions, actions}, _ctx, state) do
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:subscription, matching_function}, _ctx, state) do
    {:ok, %{state | matching_functions: [matching_function | state.matching_functions]}}
  end

  defp maybe_send_event_to_controller(event, state) do
    if Enum.any?(state.matching_functions, & &1.(event)) do
      send(state.controller_pid, event)
    end
  end
end
