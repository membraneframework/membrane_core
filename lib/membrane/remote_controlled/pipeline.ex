defmodule Membrane.RemoteControlled.Pipeline do
  @moduledoc """
  `Membrane.RemoteControlled.Pipeline` is a basic `Membrane.Pipeline` implementation that can be
  controlled by a controlling process.

  The controlling process can request the execution of arbitrary
  valid `Membrane.Pipeline.Action`:
  ```
    children = ...
    links = ...
    actions = [{:spec, %ParentSpec{children: children, links: links}}]
    Pipeline.exec_actions(pipeline, actions)
  ```

  The controlling process can also subscribe to the messages
  sent by the pipeline and later on synchroniously await for these messages:
  ```
  # subscribes to message which is sent when the pipeline enters any playback state
  Pipeline.subscribe(pipeline, %Message.PlaybackState{state: _})
  ...
  # awaits for the message sent when the pipeline enters :playing playback state
  Pipeline.await_playback_state(pipeline, :playing)
  ...
  # awaits for the message sent when the pipeline enters :stopped playback state
  Pipeline.await_playback_state(pipeline, :stopped)
  ```

  `Membrane.RemoteControlled.Pipeline` can be used when there is no need for introducing a custom
  logic in the `Membrane.Pipeline` callbacks implementation. An example of usage could be running a
  pipeline from the elixir script. `Membrane.RemoteControlled.Pipeline` sends the following messages:
  * `Membrane.RemoteControlled.Message.PlaybackState.t()` sent when pipeline enters a given playback state,
  * `Membrane.RemoteControlled.Message.StartOfStream.t()` sent
  when one of direct pipeline children informs the pipeline about start of a stream,
  * `Membrane.RemoteControlled.Message.EndOfStream.t()` sent
  when one of direct pipeline children informs the pipeline about end of a stream,
  * `Membrane.RemoteControlled.Message.Notification.t()` sent when pipeline
  receives notification from one of its children,
  * `Membrane.RemoteControlled.Message.Terminated.t()` sent when the pipeline gracefully terminates.
  """

  use Membrane.Pipeline

  alias Membrane.Pipeline
  alias Membrane.RemoteControlled.Message

  alias Membrane.RemoteControlled.Message.{
    EndOfStream,
    Notification,
    PlaybackState,
    StartOfStream,
    Terminated
  }

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

  defmacrop pin_leaf_nodes(ast) do
    quote do
      Macro.postwalk(unquote(ast), fn node ->
        if not Macro.quoted_literal?(node) and match?({_name, _ctx, _args}, node) do
          {_name, ctx, args} = node

          case args do
            nil -> {:^, ctx, [node]}
            _not_nil -> node
          end
        else
          node
        end
      end)
    end
  end

  defmacrop do_await(pipeline, message_type, keywords \\ []) do
    keywords = pin_leaf_nodes(keywords)

    quote do
      receive do
        %unquote(message_type){
          unquote_splicing(Macro.expand(keywords, __ENV__)),
          from: ^unquote(pipeline)
        } = msg ->
          msg
      end
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.PlaybackState()`
  message with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for any playback state change occuring in the pipeline:
    ```
    Pipeline.await_playback_state(pipeline)
    ```
  """
  @spec await_playback_state(pid()) :: Membrane.RemoteControlled.Message.PlaybackState.t()
  def await_playback_state(pipeline) do
    do_await(pipeline, PlaybackState)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.PlaybackState()`
  message with the given `state`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the pipeline's playback state to change into `:playing`:
    ```
    Pipeline.await_playback_state(pipeline, :playing)
    ```
  """
  @spec await_playback_state(pid, Membrane.PlaybackState.t()) ::
          Membrane.RemoteControlled.Message.PlaybackState.t()
  def await_playback_state(pipeline, playback_state) do
    do_await(pipeline, PlaybackState, state: playback_state)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `start_of_stream` occuring on any pad of any element in the pipeline:
    ```
    Pipeline.await_start_of_stream(pipeline)
    ```
  """
  @spec await_start_of_stream(pid) :: Membrane.RemoteControlled.Message.StartOfStream.t()
  def await_start_of_stream(pipeline) do
    do_await(pipeline, StartOfStream)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `start_of_stream` occuring on any pad of the `:element_id` element in the pipeline:
    ```
    Pipeline.await_start_of_stream(pipeline, :element_id)
    ```
  """
  @spec await_start_of_stream(pid(), Membrane.Element.name_t()) ::
          Membrane.RemoteControlled.Message.StartOfStream.t()
  def await_start_of_stream(pipeline, element) do
    do_await(pipeline, StartOfStream, element: element)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  concerning the given `element` and the `pad`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `start_of_stream` occuring on the `:pad_id` pad of the `:element_id` element in the pipeline:
    ```
    Pipeline.await_start_of_stream(pipeline, :element_id, :pad_id)
    ```
  """
  @spec await_start_of_stream(pid(), Membrane.Element.name_t(), Membrane.Pad.name_t()) ::
          Membrane.RemoteControlled.Message.StartOfStream.t()
  def await_start_of_stream(pipeline, element, pad) do
    do_await(pipeline, StartOfStream, element: element, pad: pad)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `end_of_stream` occuring on any pad of any element in the pipeline:
    ```
    Pipeline.await_end_of_stream(pipeline)
    ```
  """
  @spec await_end_of_stream(pid()) :: Membrane.RemoteControlled.Message.EndOfStream.t()
  def await_end_of_stream(pipeline) do
    do_await(pipeline, EndOfStream)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `end_of_stream` occuring on any pad of the `:element_id` element in the pipeline:
    ```
    Pipeline.await_end_of_stream(pipeline, :element_id)
    ```
  """
  @spec await_end_of_stream(pid(), Membrane.Element.name_t()) ::
          Membrane.RemoteControlled.Message.EndOfStream.t()
  def await_end_of_stream(pipeline, element) do
    do_await(pipeline, EndOfStream, element: element)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  concerning the given `element` and the `pad`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first `end_of_stream` occuring on the `:pad_id` of the `:element_id` element in the pipeline:
    ```
    Pipeline.await_end_of_stream(pipeline, :element_id, :pad_id)
    ```
  """
  @spec await_end_of_stream(pid(), Membrane.Element.name_t(), Membrane.Pad.name_t()) ::
          Membrane.RemoteControlled.Message.EndOfStream.t()
  def await_end_of_stream(pipeline, element, pad) do
    do_await(pipeline, EndOfStream, element: element, pad: pad)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.Notification()`
  message with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first notification send to any element in the pipeline:
    ```
    Pipeline.await_notification(pipeline)
    ```
  """
  @spec await_notification(pid()) :: Membrane.RemoteControlled.Message.Notification.t()
  def await_notification(pipeline) do
    do_await(pipeline, Notification)
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.Notification()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the first notification send to the `:element_id` element in the pipeline:
    ```
    Pipeline.await_notification(pipeline, :element_id)
    ```
  """
  @spec await_notification(pid(), Membrane.Notification.t()) ::
          Membrane.RemoteControlled.Message.Notification.t()
  def await_notification(pipeline, element) do
    do_await(pipeline, Notification, element: element)
  end

  @doc """
  Awaits for the `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.Terminated` message,
  which is send when the pipeline gracefully terminates.
  It is required to firstly use the `subscribe/2` to subscribe to a given message before awaiting
  for that message.

  Usage example:
    1) awaiting for the pipeline termination:
    ```
    Pipeline.await_termination(pipeline)
    ```
  """
  @spec await_termination(pid()) :: Membrane.RemoteControlled.Message.Terminated.t()
  def await_termination(pipeline) do
    do_await(pipeline, Terminated)
  end

  @doc """
  Subscribes to a given `subscription_pattern`. The `subscription_pattern` should describe some subset
  of elements of `Membrane.RemoteControlled.Pipeline.message_t()` type. The `subscription_pattern`
  must be a match pattern.


  Usage examples:
  1) making the `Membrane.RemoteControlled.Pipeline` send to the controlling process `Message.StartOfStream` message
    when any pad of the `:element_id` receives `:start_of_stream` event.

    ```
    subscribe(pipeline, %Message.StartOfStream{element: :element_id, pad: _})
    ```

  2) making the `Membrane.RemoteControlled.Pipeline` send to the controlling process `Message.PlaybackState` message when the pipeline playback state changes to any state
    (that is - for all the :stopped, :prepared and :playing playback states).

    ```
    subscribe(pipeline, %Message.PlaybackState{state: _})
    ```
  """
  defmacro subscribe(pipeline, subscription_pattern) do
    quote do
      send(
        unquote(pipeline),
        {:subscription, fn message -> match?(unquote(subscription_pattern), message) end}
      )
    end
  end

  @doc """
  Sends a list of `Pipeline.Action.t()` to the given `Membrane.RemoteControlled.Pipeline` for execution.

  Usage example:
    1) making the `Membrane.RemoteControlled.Pipeline` start the `Membrane.ParentSpec`
       specified in the action.
    ```
    children = ...
    links = ...
    actions = [{:spec, %ParentSpec{children: children, links: links}}]
    Pipeline.exec_actions(pipeline, actions)
    ```
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
    pipeline_event = %Message.PlaybackState{from: self(), state: :prepared}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    pipeline_event = %Message.PlaybackState{from: self(), state: :playing}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    pipeline_event = %Message.PlaybackState{from: self(), state: :stopped}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    pipeline_event = %Message.PlaybackState{from: self(), state: :prepared}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_terminating(_ctx, state) do
    pipeline_event = %Message.PlaybackState{from: self(), state: :terminating}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream(element_name, pad_ref, _ctx, state) do
    pipeline_event = %Message.EndOfStream{from: self(), element: element_name, pad: pad_ref}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_start_of_stream(element_name, pad_ref, _ctx, state) do
    pipeline_event = %Message.StartOfStream{from: self(), element: element_name, pad: pad_ref}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_notification(notification, element, _ctx, state) do
    pipeline_event = %Message.Notification{from: self(), data: notification, element: element}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_info({:exec_actions, actions}, _ctx, state) do
    {{:ok, actions}, state}
  end

  @impl true
  def handle_info({:subscription, pattern}, _ctx, state) do
    {:ok, %{state | matching_functions: [pattern | state.matching_functions]}}
  end

  @impl true
  def handle_shutdown(reason, state) do
    pipeline_event = %Message.Terminated{from: self(), reason: reason}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    :ok
  end

  defp send_event_to_controller_if_subscribed(message, state) do
    if Enum.any?(state.matching_functions, & &1.(message)) do
      send(state.controller_pid, message)
    end
  end
end
