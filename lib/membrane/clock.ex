defmodule Membrane.Clock do
  use GenServer
  require Membrane.Core.Message
  alias Membrane.Time
  alias Membrane.Core.Message

  def start_link(options \\ [], gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, options, gen_server_options)
  end

  def start_link!(options \\ [], gen_server_options \\ []) do
    {:ok, clock} = start_link(options, gen_server_options)
    clock
  end

  @impl GenServer
  def init(options) do
    state =
      %{ratio: 1, subscribees: MapSet.new()}
      |> Map.merge(
        case {options[:proxy], options[:proxy_to]} do
          {_, pid} when is_pid(pid) ->
            Message.send(pid, :clock_subscribe, self())
            %{proxy: true, proxy_to: pid}

          {true, _} ->
            %{proxy: true, proxy_to: nil}

          _ ->
            %{init_time: nil, recv_time: 0, till_next: nil, proxy: false}
        end
      )

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:membrane_clock_update, till_next}, %{proxy: false} = state) do
    {:noreply, handle_clock_update(till_next, state)}
  end

  @impl GenServer
  def handle_info({:membrane_clock_ratio, _pid, ratio}, %{proxy: true} = state) do
    {:noreply, send_and_update_ratio(ratio, state)}
  end

  @impl GenServer
  def handle_info(Message.new(:proxy_to, proxy_to), %{proxy: true} = state) do
    if state.proxy_to do
      Message.send(state.proxy_to, :clock_unsubscribe, self())
    end

    state = %{state | proxy_to: proxy_to}

    state =
      if proxy_to do
        Message.send(proxy_to, :clock_subscribe, self())
        state
      else
        send_and_update_ratio(1, state)
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:clock_subscribe, pid), state) do
    send(pid, {:membrane_clock_ratio, self(), state.ratio})
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
    state = %{state | recv_time: recv_time, till_next: new_till_next}
    send_and_update_ratio(ratio, state)
  end

  defp send_and_update_ratio(ratio, state) do
    state.subscribees |> Enum.each(&send(&1, {:membrane_clock_ratio, self(), ratio}))
    %{state | ratio: ratio}
  end
end
