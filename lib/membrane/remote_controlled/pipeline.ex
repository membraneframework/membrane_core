defmodule Membrane.RemoteControlled.Pipeline do
  @moduledoc """
  This Pipeline is intended to be used for simple pipelines that can be controlled by
  sending actions from an external element.
  """

  use Membrane.Pipeline

  alias Membrane.Pipeline

  defmodule State do
    @enforce_keys [:controller_pid]
    defstruct @enforce_keys ++ [subscriptions: %{}]
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
  def handle_element_end_of_stream({element_name, pad_ref}, _ctx, state) do
    subscription_key = {:end_of_stream, element_name, pad_ref}
    state = mark_subscribed_event_occurred(subscription_key, state)

    {:ok, state}
  end

  @impl true
  def handle_element_start_of_stream({element_name, pad_ref}, _ctx, state) do
    subscription_key = {:start_of_stream, element_name, pad_ref}
    state = mark_subscribed_event_occurred(subscription_key, state)

    {:ok, state}
  end

  @impl true
  def handle_other({:exec_actions, actions}, _ctx, state) do
    {{:ok, actions}, state}
  end

  @spec subscribe(pid(), {:start_of_stream | :end_of_stream, Membrane.Element.name_t(), Membrane.Pad.name_t()}) :: :ok
  def subscribe(pipeline, subscription_key) do
    :ok
  end

  @spec exec_actions(pid(), [Pipeline.Action.t()]) :: :ok
  def exec_actions(pipeline, actions) do
    send(pipeline, {:exec_actions, actions})
    :ok
  end

  defp mark_subscribed_event_occurred(subscription_key, state) do
    if Map.has_key?(state.subscriptions, subscription_key) do
      %State{state | subscriptions: Map.update!(state.subscriptions, subscription_key, &(&1 + 1))}
    else
      state
    end
  end

  defp mark_subscribed_event_awaited(subscription_key, state) do
    if Map.has_key?(state.subscriptions, subscription_key) do
      %State{state | subscriptions: Map.update!(state.subscriptions, subscription_key, &(&1 - 1))}
    else
      state
    end
  end
end
