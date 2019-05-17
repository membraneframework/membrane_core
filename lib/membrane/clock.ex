defmodule Membrane.Clock do
  use GenServer
  require Membrane.Core.Message
  alias Membrane.Time
  alias Membrane.Core.Message

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  @impl GenServer
  def init(_options) do
    {:ok, %{init_time: nil, recv_time: 0, till_next: nil, ratio: 1, subscribees: MapSet.new()}}
  end

  @impl GenServer
  def handle_info({:membrane_clock_update, till_next}, state) do
    {:noreply, handle_clock_update(till_next, state)}
  end

  @impl GenServer
  def handle_info(Message.new(:clock_subscribe, pid), state) do
    Message.send(pid, :clock_update, [self(), state.ratio])
    Process.monitor(pid)
    state = state |> Map.update!(:subscribees, &MapSet.put(&1, pid))
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:clock_unsubscribe, pid), state) do
    Process.demonitor(pid)
    handle_unsubscribe(pid, state)
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    handle_unsubscribe(pid, state)
  end

  defp handle_unsubscribe(pid, state) do
    state = state |> Map.update!(:subscribees, &MapSet.delete(&1, pid))
    {:noreply, state}
  end

  defp handle_clock_update(till_next, %{init_time: nil} = state) do
    %{state | init_time: Time.monotonic_time(), till_next: till_next}
  end

  defp handle_clock_update(new_till_next, state) do
    use Ratio
    %{till_next: {nom, denom}, recv_time: recv_time} = state
    recv_time = recv_time + (Time.milliseconds(nom) <|> denom)
    ratio = recv_time / (Time.monotonic_time() - state.init_time)
    state.subscribees |> Enum.each(&Message.send(&1, :clock_update, [self(), state.ratio]))
    %{state | recv_time: recv_time, till_next: new_till_next, ratio: ratio}
  end
end
