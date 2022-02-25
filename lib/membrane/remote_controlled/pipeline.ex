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

  defmodule Message do
    @enforce_keys [:from, :body]
    defstruct @enforce_keys

    defmodule PlaybackState do
      defstruct [:state]
    end

    defmodule Notification do
      defstruct [:element, :data]
    end

    defmodule EndOfStream do
      defstruct [:element, :pad]
    end

    defmodule StartOfStream do
      defstruct [:element, :pad]
    end
  end

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
      %Message{from: ^pipeline, body: %Message.PlaybackState{}} = message -> message
    end
  end

  def await_playback_state(pipeline, playback_state) do
    receive do
      %Message{from: ^pipeline, body: %Message.PlaybackState{state: ^playback_state}} = message -> message
    end
  end


  def await_notification(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.Notification{}} = message -> message
    end
  end

  def await_notification(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.Notification{element: ^element}} = message -> message
    end
  end

  def await_start_of_stream(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{}} = message -> message
    end
  end

  def await_start_of_stream(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{element: ^element}} = message -> message
    end
  end

  def await_start_of_stream(pipeline, element, pad) do
    receive do
      %Message{from: ^pipeline, body: %Message.StartOfStream{element: ^element, pad: ^pad}} = message -> message
    end
  end

  def await_end_of_stream(pipeline) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{}} = message -> message
    end
  end

  def await_end_of_stream(pipeline, element) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{element: ^element}} = message -> message
    end
  end

  def await_end_of_stream(pipeline, element, pad) do
    receive do
      %Message{from: ^pipeline, body: %Message.EndOfStream{element: ^element, pad: ^pad}} = message -> message
    end
  end

  defmacro await_generic(pipeline, message_type, keywords\\[]) do
    quote do
      receive do
      %Message{from: unquote(pipeline), body: %Membrane.RemoteControlled.Pipeline.Message.unquote(message_type){unquote_splicing(Macro.expand(keywords, __ENV__))} }= msg -> msg
      end
    end
  end



  defmacro await_generic2(pipeline, message) do
    quote do
      receive do
        %Message{from: unquote(Macro.expand(pipeline, __ENV__)), body: unquote(Macro.expand(message, __ENV__)) } = msg -> msg
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
        {:subscription, fn x -> match?(%Message{body: unquote(subscription_pattern) }, x) end}
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
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :playing}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :stopped}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :prepared}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_terminating(_ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.PlaybackState{state: :terminating}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.EndOfStream{element: element_name, pad: pad_ref}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_element_start_of_stream({element_name, pad_ref}, _ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.StartOfStream{element: element_name, pad: pad_ref}}
    maybe_send_event_to_controller(pipeline_event, state)
    {:ok, state}
  end

  @impl true
  def handle_notification(notification, element, _ctx, state) do
    pipeline_event = %Message{from: self(), body: %Message.Notification{data: notification, element: element}}
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

  defp maybe_send_event_to_controller(message, state) do
    if Enum.any?(state.matching_functions, & &1.(message)) do
      send(state.controller_pid, message)
    end
  end

end
