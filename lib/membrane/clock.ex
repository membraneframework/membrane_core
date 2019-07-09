defmodule Membrane.Clock do
  @moduledoc """
  Clock is a Membrane utility that allows elements to measure time according to
  a particular clock, which can be e.g. a soundcard hardware clock.

  Internally, Clock is a GenServer process that can be sent _updates_ (see `t:update_t`),
  which are messages containing amount of time between current and subsequent update
  according to some custom clock. Basing on updates, Clock calculates a _ratio_
  between the Erlang clock and the custom clock, that is broadcasted to
  _subscribers_ (see `subscribe/1`)- processes willing to synchronize to the custom clock. Subscribers
  can adjust their timers according to received ratio - timers started with `:timer`
  action in elements do it automatically. Initial ratio is equal to 1, which means
  that if no updates are received, clock is synchronized to the Erlang clock.

  ## Proxy mode
  Clock can work in _proxy_ mode, which means it cannot receive updates, but
  it receives ratio from another clock instead, and forwards it to subscribers.
  Proxy mode is enabled with `proxy_for: pid` or `proxy: true` (no initial proxy)
  option, and the proxy is set/changed using `proxy_for/2`.
  """
  use GenServer
  require Membrane.Core.Message
  alias Membrane.Time
  alias Membrane.Core.Message

  @type update_t ::
          {:membrane_clock_update,
           (milliseconds :: non_neg_integer | Ratio.t())
           | {milliseconds :: non_neg_integer, denominator :: pos_integer}}

  def start_link(options \\ [], gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, options, gen_server_options)
  end

  def start_link!(options \\ [], gen_server_options \\ []) do
    {:ok, clock} = start_link(options, gen_server_options)
    clock
  end

  def subscribe(clock) do
    Message.send(clock, :clock_subscribe, self())
    :ok
  end

  def proxy_for(clock, clock_to_proxy_for) do
    Message.send(clock, :proxy_for, clock_to_proxy_for)
    :ok
  end

  @impl GenServer
  def init(options) do
    state =
      %{ratio: 1, subscribers: %{}}
      |> Map.merge(
        case {options[:proxy], options[:proxy_for]} do
          {_, pid} when is_pid(pid) ->
            Message.send(pid, :clock_subscribe, self())
            %{proxy: true, proxy_for: pid}

          {true, _} ->
            %{proxy: true, proxy_for: nil}

          _ ->
            %{init_time: nil, clock_time: 0, till_next: nil, proxy: false}
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
  def handle_info(Message.new(:proxy_for, proxy_for), %{proxy: true} = state) do
    if state.proxy_for do
      Message.send(state.proxy_for, :clock_unsubscribe, self())
    end

    state = %{state | proxy_for: proxy_for}

    state =
      if proxy_for do
        Message.send(proxy_for, :clock_subscribe, self())
        state
      else
        send_and_update_ratio(1, state)
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:clock_subscribe, pid), state) do
    send(pid, {:membrane_clock_ratio, self(), state.ratio})
    monitor = Process.monitor(pid)
    state = state |> put_in([:subscribers, pid], %{monitor: monitor})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(Message.new(:clock_unsubscribe, pid), state) do
    Process.demonitor(state.subscribers[pid].monitor)
    handle_unsubscribe(pid, state)
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    handle_unsubscribe(pid, state)
  end

  defp handle_unsubscribe(pid, state) do
    state = state |> Bunch.Access.delete_in([:subscribers, pid])
    {:noreply, state}
  end

  defp handle_clock_update({nom, denom}, state) do
    handle_clock_update(Ratio.new(nom, denom), state)
  end

  defp handle_clock_update(till_next, %{init_time: nil} = state) do
    %{state | init_time: Time.monotonic_time(), till_next: till_next}
  end

  defp handle_clock_update(till_next, state) do
    use Ratio

    if till_next < 0 do
      raise "Clock update time cannot be negative, received: #{inspect(till_next)}"
    end

    %{till_next: from_previous, clock_time: clock_time} = state
    clock_time = clock_time + from_previous * Time.millisecond(1)
    ratio = clock_time / (Time.monotonic_time() - state.init_time)
    state = %{state | clock_time: clock_time, till_next: till_next}
    send_and_update_ratio(ratio, state)
  end

  defp send_and_update_ratio(ratio, state) do
    state.subscribers |> Bunch.KVList.each_key(&send(&1, {:membrane_clock_ratio, self(), ratio}))
    %{state | ratio: ratio}
  end
end
