defmodule Membrane.RemoteControlled.Pipeline do
  @moduledoc """
  `Membrane.RemoteControlled.Pipeline` is a basic `Membrane.Pipeline` implementation that can be
  controlled by a controlling process. The controlling process can request the execution of arbitrary
  valid `Membrane.Pipeline.Action`. The controlling process can also subscribe and await for
  `Membrane.RemoteControlled.Pipeline.message_t()` that are sent by the pipeline.
  `Membrane.RemoteControlled.Pipeline` can be used when there is no need for introducing a custom
  logic in the `Membrane.Pipeline` callbacks implementation. An example of usage could be running a
  pipeline from the elixir script. `Membrane.RemoteControlled.Pipeline` sends the following messages:
  * `{:playback_state, Membrane.PlaybackState.t()}` sent when pipeline enters a given playback state,
  * `{:start_of_stream | :end_of_stream, Membrane.Element.name_t(), Membrane.Pad.name_t()}` sent
  when one of direct pipeline children informs the pipeline about start or end of stream,
  * `{:notification, Membrane.Element.name_t(), Membrane.Notification.t()}` sent when pipeline
  receives notification from one of its children.
  """

  use Membrane.Pipeline

  alias Membrane.Pipeline

  @type message_t ::
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
    Pipeline.start_link(__MODULE__, %{controller_pid: self()}, process_options)
  end

  @doc """
  Does the same as the `start_link/1` but starts the process outside of the supervision tree.
  """
  @spec start(GenServer.options()) :: GenServer.on_start()
  def start(process_options \\ []) do
    Pipeline.start(__MODULE__, %{controller_pid: self()}, process_options)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Pipeline.message_t()` that matches the given `pattern`.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` before awaiting
  any messages. `pattern` has to be a match pattern.
  """
  # def await(pipeline, pattern, timeout\\1_000) do
  #     receive do
  #       {^pipeline, event} -> if do_pattern_match?(event, pattern) do event else await(pipeline, pattern) end
  #     after timeout -> nil
  #     end
  # end

  def await_playback_state(pipeline) do
    receive do
      {^pipeline, {:playback_state, playback_state}} -> {:playback_state, playback_state}
    end
  end

  def await_playback_state(pipeline, playback_state) do
    receive do
      {^pipeline, {:playback_state, ^playback_state}} -> {:playback_state, playback_state}
    end
  end


  def await_notification(pipeline) do
    receive do
      {^pipeline, {:notification, element, msg}} -> {:notification, element, msg}
    end
  end

  def await_notification(pipeline, element) do
    receive do
      {^pipeline, {:notification, ^element, msg}} -> {:notification, element, msg}
    end
  end

  def await_start_of_stream(pipeline) do
    receive do
      {^pipeline, {:start_of_stream, element, pad}} -> {:start_of_stream, element, pad}
    end
  end

  def await_start_of_stream(pipeline, element) do
    receive do
      {^pipeline, {:start_of_stream, ^element, pad}} -> {:start_of_stream, element, pad}
    end
  end

  def await_start_of_stream(pipeline, element, pad) do
    receive do
      {^pipeline, {:start_of_stream, ^element, ^pad}} -> {:start_of_stream, element, pad}
    end
  end

  def await_end_of_stream(pipeline) do
    receive do
      {^pipeline, {:end_of_stream, element, pad}} -> {:end_of_stream, element, pad}
    end
  end

  def await_end_of_stream(pipeline, element) do
    receive do
      {^pipeline, {:end_of_stream, ^element, pad}} -> {:end_of_stream, element, pad}
    end
  end

  def await_end_of_stream(pipeline, element, pad) do
    receive do
      {^pipeline, {:end_of_stream, ^element, ^pad}} -> {:end_of_stream, element, pad}
    end
  end


  @doc """
  Subscribes to a given `subscription_pattern`. The `subscription_pattern` should describe some subset
  of elements of `Membrane.RemoteControlled.Pipeline.message_t()` type. The `subscription_pattern`
  must be a match pattern.

      subscribe(pid, {:playback_state, _})

  Such call would make the `Membrane.RemoteControlled.Pipeline` to send all `:playback_state` messages
  to the controlling process.
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
  def handle_other({:subscription, pattern}, _ctx, state) do
    {:ok, %{state | matching_functions: [pattern | state.matching_functions]}}
  end

  defp maybe_send_event_to_controller(event, state) do
    if Enum.any?(state.matching_functions, & &1.(event)) do
      send(state.controller_pid, {self(), event})
    end
  end

  # defp do_pattern_match?(event, pattern) do
  #   event_as_list = event |> Tuple.to_list()
  #   pattern_as_list = pattern |> Tuple.to_list()
  #   event_as_list |> Enum.slice(0..length(pattern_as_list)) |> Enum.zip(pattern_as_list) |>
  #     Enum.all?(fn {event_at_given_position, pattern_at_given_position}-> do_pattern_match_at_given_position?(event_at_given_position, pattern_at_given_position) end)
  # end

  # defp do_pattern_match_at_given_position?(_event_at_given_position, pattern_at_given_position) when pattern_at_given_position==:any do
  #   true
  # end

  # defp do_pattern_match_at_given_position?(event_at_given_position, pattern_at_given_position) do
  #   event_at_given_position==pattern_at_given_position
  # end


end
