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
  alias Membrane.RemoteControlled.Message


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
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.PlaybackState()` message with no further constraints,
  sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_playback_state(pid()) :: Membrane.RemoteControlled.Message.t()
  def await_playback_state(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.PlaybackState{}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.PlaybackState()` message with the given `state`,
  sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_playback_state(pid, Membrane.PlaybackState.t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_playback_state(pipeline, playback_state) do
    receive do
      %Message{from: ^pipeline, body: %Message.PlaybackState{state: ^playback_state}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_start_of_stream(pid) :: Membrane.RemoteControlled.Message.t()
  def await_start_of_stream(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_start_of_stream(pid(), Membrane.Element.name_t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_start_of_stream(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{element: ^element}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.StartOfStream()` message
  concerning the given `element` and the `pad`, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_start_of_stream(pid(), Membrane.Element.name_t(), Membrane.Pad.name_t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_start_of_stream(pipeline, element, pad) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{element: ^element, pad: ^pad}} =
          message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_end_of_stream(pid()) :: Membrane.RemoteControlled.Message.t()
  def await_end_of_stream(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_end_of_stream(pid(), Membrane.Element.name_t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_end_of_stream(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{element: ^element}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.EndOfStream()` message
  concerning the given `element` and the `pad`, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_end_of_stream(pid(), Membrane.Element.name_t(), Membrane.Pad.name_t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_end_of_stream(pipeline, element, pad) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{element: ^element, pad: ^pad}} =
          message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.Notification()`
  message with no further constraints, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_notification(pid()) :: Membrane.RemoteControlled.Message.t()
  def await_notification(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.Notification{}} = message ->
        message
    end
  end

  @doc """
  Awaits for the first `Membrane.RemoteControlled.Message()` wrapping the `Membrane.RemoteControlled.Message.Notification()` message
  concerning the given `element`, sent by the process with `pipeline` pid.
  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  @spec await_notification(pid(), Membrane.Notification.t()) ::
          Membrane.RemoteControlled.Message.t()
  def await_notification(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.Notification{element: ^element}} = message ->
        message
    end
  end

  @doc """
  Awaits for a `Membrane.RemoteControlled.Message()` wrapping the given `message_type`, with some fields specified according to the `keywords` list, sent by the
  process with the `pipeline` pid.

  Arguments:
    pipeline - pid of the pipeline process
    message_type - an atom describing the desired message type (i.e. PlaybackState or Notification)
    keywords - keywords list with keys being the field names of the given `message_type` structure.

  Exemplary usage:
    `await_generic(pipeline, StartOfStream, element: :b)`

    Such a call would await for the first message matching the following pattern: `%Message{from: ^pipeline, body: Message.StartOfStream{element: :b}}`
    Note, that a message would will matched independently of the value of the `:input` field of the `Message.StartOfStream` structure.

  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  defmacro await_generic(pipeline, message_type, keywords \\ []) do
    keywords = pin_leaf_nodes(keywords)

    quote do
      receive do
        %Message{
          from: ^unquote(pipeline),
          body: %Membrane.RemoteControlled.Message.unquote(message_type){
            unquote_splicing(Macro.expand(keywords, __ENV__))
          }
        } = msg ->
          msg
      end
    end
  end

  @doc """
  Awaits for a `Membrane.RemoteControlled.Message()`, which `:body` field matches the given `message_pattern`, sent by the
  process with the `pipeline` pid.

  Arguments:
    pipeline - pid of the pipeline process
    message_pattern - an pattern describing the desired specific message (i.e. %PlaybackState{state: :playing}). If values of some specific messages field are irrevelant then those fields should be omited
    (usage of a wildcard `_` sign will result in compilation error)

  Exemplary usage:
    `await_generic(pipeline, %StartOfStream{element: :b})`

    Such a call would await for the first message matching the following pattern: `%Message{from: ^pipeline, body: Message.StartOfStream{element: :b}}`
    Note, that a message will be matched independently of the value of the `:input` field of the `Message.StartOfStream` structure.

  It is required to firstly use the `Membrane.RemoteControlled.Pipeline.subscribe/2` to subscribe for given message before awaiting
  for that message.
  """
  defmacro await_generic_with_alternative_syntax(pipeline, message_pattern) do
    message_pattern = pin_leaf_nodes(message_pattern)

    quote do
      receive do
        %Message{
          from: ^unquote(Macro.expand(pipeline, __ENV__)),
          body: unquote(Macro.expand(message_pattern, __ENV__))
        } = msg ->
          msg
      end
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
        {:subscription, fn x -> match?(%Message{body: unquote(subscription_pattern)}, x) end}
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
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :prepared}}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :playing}}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :stopped}}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :prepared}}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_terminating(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :terminating}}
    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = %Message{
      from: self(),
      body: %Message.EndOfStream{element: element_name, pad: pad_ref}
    }

    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_start_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = %Message{
      from: self(),
      body: %Message.StartOfStream{element: element_name, pad: pad_ref}
    }

    send_event_to_controller_if_subscribed(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_notification(notification, element, _ctx, state) do
    pipeline_event = %Message{
      from: self(),
      body: %Message.Notification{data: notification, element: element}
    }

    send_event_to_controller_if_subscribed(pipeline_event, state)
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

  defp send_event_to_controller_if_subscribed(message, state) do
    if Enum.any?(state.matching_functions, & &1.(message)) do
      send(state.controller_pid, message)
    end
  end

  defp pin_leaf_nodes(ast) do
    Macro.postwalk(ast, fn node ->
      if not Macro.quoted_literal?(node) and match?({_name, _ctx, _args}, node) do
        {_name, ctx, args} = node

        case args do
          nil -> {:^, ctx, [node]}
          _ -> node
        end
      else
        node
      end
    end)
  end
end
