defmodule Membrane.Clock do
  use GenServer
  alias Membrane.Time

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  @impl GenServer
  def init(_options) do
    {:ok, %{init_time: nil, recv_time: 0, till_next: nil, ratio: 1}}
  end

  @impl GenServer
  def handle_info({:membrane_clock_update, till_next}, state) do
    {:noreply, handle_clock_update(till_next, state)}
  end

  @impl GenServer
  def handle_info({:membrane_clock_subscribe, pid, interval, init_time}, state) do
    handle_tick(pid, interval, init_time, state.ratio)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tick, pid, interval, init_time, seq_no}, state) do
    handle_tick(pid, interval, init_time, seq_no, state.ratio)
    {:noreply, state}
  end

  defp handle_tick(pid, interval, init_time, seq_no \\ 1, ratio) do
    use Ratio
    time = (init_time + ratio * interval * seq_no) |> Ratio.floor() |> Time.to_milliseconds()
    # IO.inspect(time)

    Process.send_after(pid, :tick, time, abs: true)
    Process.send_after(self(), {:tick, pid, interval, init_time, seq_no + 1}, time, abs: true)
  end

  defp handle_clock_update(till_next, %{init_time: nil} = state) do
    %{state | init_time: Time.monotonic_time(), till_next: till_next}
  end

  defp handle_clock_update(new_till_next, state) do
    use Ratio
    %{till_next: {nom, denom}, recv_time: recv_time} = state
    recv_time = recv_time + (Time.milliseconds(nom) <|> denom)
    ratio = recv_time / (Time.monotonic_time() - state.init_time)
    %{state | recv_time: recv_time, till_next: new_till_next, ratio: ratio}
  end
end
