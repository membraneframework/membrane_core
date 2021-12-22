defmodule Membrane.RemoteControlled.Pipeline do
  @moduledoc """
  This Pipeline is intended to be used for simple pipelines that can be controlled by
  sending actions from an external element.
  """

  use Membrane.Pipeline

  alias Membrane.Pipeline

  defmodule State do
    @enforce_keys [:controller_pid]
    defstruct @enforce_keys ++ [matching_functions: []]
  end

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(process_options \\ []) do
    args = [__MODULE__, %{controller_pid: self()}, process_options]
    apply(Pipeline, :start_link, args)
  end

  @spec start(GenServer.options()) :: GenServer.on_start()
  def start(process_options \\ []) do
    args = [__MODULE__, %{controller_pid: self()}, process_options]
    apply(Pipeline, :start, args)
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
  def handle_other({:exec_actions, actions}, _ctx, state) do
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:subscription, matching_function}, _ctx, state) do
    {:ok, %{state | matching_functions: [matching_function | state.matching_functions]}}
  end

  defmacro await(pattern) do
    quote do
      unquote(pattern) =
        receive do
          unquote(pattern) = msg -> msg
        end
    end
  end

  defmacro subscribe(pipeline, subscription_pattern) do
    quote do
      send(
        unquote(pipeline),
        {:subscription, fn x -> match?(unquote(subscription_pattern), x) end}
      )
    end
  end

  @spec exec_actions(pid(), [Pipeline.Action.t()]) :: :ok
  def exec_actions(pipeline, actions) do
    send(pipeline, {:exec_actions, actions})
    :ok
  end

  defp maybe_send_event_to_controller(event, state) do
    if Enum.any?(state.matching_functions, & &1.(event)) do
      send(state.controller_pid, event)
    end
  end
end
