defmodule Membrane.Clock do
  @moduledoc """
  Clock is a Membrane utility that allows elements to measure time according to
  a particular clock, which can be e.g. a soundcard hardware clock.

  Internally, Clock is a GenServer process that can receive _updates_ (see `t:update_message_t/0`),
  which are messages containing amount of time until the next update.
  For example, a sink playing audio to the sound card can send an update before
  each write to the sound card buffer (for practical reasons that can be done every
  100 or 1000 writes). Although it might be more intuitive to send updates with
  the time passed, in practice the described approach turns out to be more convenient,
  as it simplifies the first update.

  Basing on updates, Clock calculates the `t:ratio_t/0` of its time to the reference
  time. The reference time can be configured with `:time_provider` option. The ratio
  is broadcasted (see `t:ratio_message_t/0`) to _subscribers_ (see `subscribe/2`)
  - processes willing to synchronize to the custom clock. Subscribers can adjust
  their timers according to received ratio - timers started with
  `t:Membrane.Element.Action.start_timer_t/0` action in elements do it automatically.
  Initial ratio is equal to 1, which means that if no updates are received,
  Clock is synchronized to the reference time.

  ## Proxy mode
  Clock can work in _proxy_ mode, which means it cannot receive updates, but
  it receives ratio from another clock instead, and forwards it to subscribers.
  Proxy mode is enabled with `proxy_for: pid` or `proxy: true` (no initial proxy)
  option, and the proxy is set/changed using `proxy_for/2`.
  """
  use Bunch
  use GenServer

  alias Membrane.Core.Message
  alias Membrane.Time

  @type t :: pid

  @typedoc """
  Ratio of the Clock time to the reference time.
  """
  @type ratio_t :: Ratio.t() | non_neg_integer

  @typedoc """
  Update message received by the Clock. It should contain the time till the next
  update.
  """
  @type update_message_t ::
          {:membrane_clock_update,
           milliseconds ::
             non_neg_integer
             | Ratio.t()
             | {numerator :: non_neg_integer, denominator :: pos_integer}}

  @typedoc """
  Ratio message sent by the Clock to all its subscribers. It contains the ratio
  of the custom clock time to the reference time.
  """
  @type ratio_message_t :: {:membrane_clock_ratio, clock :: pid, ratio_t}

  @typedoc """
  Options accepted by `start_link/2` and `start/2` functions.

  They are the following:
    - `time_provider` - function providing the reference time in milliseconds
    - `proxy` - determines whether the Clock should work in proxy mode
    - `proxy_for` - enables the proxy mode and sets proxied Clock to pid

  Check the moduledoc for more details.
  """
  @type option_t ::
          {:time_provider, (() -> Time.t())}
          | {:proxy, boolean}
          | {:proxy_for, pid | nil}

  @spec start_link([option_t], GenServer.options()) :: GenServer.on_start()
  def start_link(options \\ [], gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, options, gen_server_options)
  end

  @spec start([option_t], GenServer.options()) :: GenServer.on_start()
  def start(options \\ [], gen_server_options \\ []) do
    GenServer.start(__MODULE__, options, gen_server_options)
  end

  @doc """
  Subscribes `pid` for receiving `t:ratio_message_t/0` messages from the clock.

  This function can be called multiple times from the same process. To unsubscribe,
  `unsubscribe/2` should be called the same amount of times. The subscribed pid
  always receives one message, regardless of how many times it called `subscribe/2`.
  """
  @spec subscribe(t, subscriber :: pid) :: :ok
  def subscribe(clock, pid \\ self()) do
    GenServer.cast(clock, {:clock_subscribe, pid})
  end

  @doc """
  Unsubscribes `pid` from receiving `t:ratio_message_t/0` messages from the clock.

  For unsubscription to take effect, `unsubscribe/2` should be called the same
  amount of times as `subscribe/2`.
  """
  @spec unsubscribe(t, subscriber :: pid) :: :ok
  def unsubscribe(clock, pid \\ self()) do
    GenServer.cast(clock, {:clock_unsubscribe, pid})
  end

  @doc """
  Sets a new proxy clock to `clock_to_proxy_for`.
  """
  @spec proxy_for(t, clock_to_proxy_for :: pid | nil) :: :ok
  def proxy_for(clock, clock_to_proxy_for) do
    GenServer.cast(clock, {:proxy_for, clock_to_proxy_for})
  end

  @impl GenServer
  def init(options) do
    proxy_opts = get_proxy_options(options[:proxy], options[:proxy_for])

    state =
      %{
        ratio: 1,
        subscribers: %{},
        time_provider: options |> Keyword.get(:time_provider, fn -> Time.monotonic_time() end)
      }
      |> Map.merge(proxy_opts)

    if pid = proxy_opts[:proxy_for], do: Message.send(pid, :clock_subscribe, self())

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:proxy_for, proxy_for}, %{proxy: true} = state) do
    if state.proxy_for, do: unsubscribe(state.proxy_for)

    state = %{state | proxy_for: proxy_for}

    state =
      if proxy_for do
        subscribe(proxy_for)
        state
      else
        broadcast_and_update_ratio(1, state)
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:clock_subscribe, pid}, state) do
    state
    |> update_in([:subscribers, pid], fn
      nil ->
        send_ratio(pid, state.ratio)
        monitor = Process.monitor(pid)
        %{monitor: monitor, subscriptions: 1}

      %{subscriptions: subs} = subscriber ->
        %{subscriber | subscriptions: subs + 1}
    end)
    ~> {:noreply, &1}
  end

  @impl GenServer
  def handle_cast({:clock_unsubscribe, pid}, state) do
    if Map.has_key?(state.subscribers, pid) do
      {subs, state} =
        state |> Bunch.Access.get_updated_in([:subscribers, pid, :subscriptions], &(&1 - 1))

      if subs == 0, do: handle_unsubscribe(pid, state), else: state
    else
      state
    end
    ~> {:noreply, &1}
  end

  @impl GenServer
  def handle_info({:membrane_clock_update, till_next}, %{proxy: false} = state) do
    {:noreply, handle_clock_update(till_next, state)}
  end

  @impl GenServer
  def handle_info({:membrane_clock_ratio, pid, ratio}, %{proxy: true, proxy_for: pid} = state) do
    {:noreply, broadcast_and_update_ratio(ratio, state)}
  end

  @impl GenServer
  # When ratio from previously proxied clock comes in after unsubscribing
  def handle_info({:membrane_clock_ratio, _pid, _ratio}, %{proxy: true} = state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, handle_unsubscribe(pid, state)}
  end

  defp get_proxy_options(proxy, proxy_for)
  defp get_proxy_options(_proxy, pid) when is_pid(pid), do: %{proxy: true, proxy_for: pid}
  defp get_proxy_options(true, _proxy_for), do: %{proxy: true, proxy_for: nil}

  defp get_proxy_options(_proxy, _proxy_for),
    do: %{init_time: nil, clock_time: 0, till_next: nil, proxy: false}

  defp handle_unsubscribe(pid, state) do
    Process.demonitor(state.subscribers[pid].monitor, [:flush])
    state |> Bunch.Access.delete_in([:subscribers, pid])
  end

  defp handle_clock_update({nom, denom}, state) do
    handle_clock_update(Ratio.new(nom, denom), state)
  end

  defp handle_clock_update(till_next, state) do
    use Ratio

    if till_next < 0 do
      raise "Clock update time cannot be negative, received: #{inspect(till_next)}"
    end

    till_next = till_next * Time.millisecond()

    case state.init_time do
      nil -> %{state | init_time: state.time_provider.(), till_next: till_next}
      _init_time -> do_handle_clock_update(till_next, state)
    end
  end

  defp do_handle_clock_update(till_next, state) do
    use Ratio
    %{till_next: from_previous, clock_time: clock_time} = state
    clock_time = clock_time + from_previous
    ratio = clock_time / (state.time_provider.() - state.init_time)
    state = %{state | clock_time: clock_time, till_next: till_next}
    broadcast_and_update_ratio(ratio, state)
  end

  defp broadcast_and_update_ratio(ratio, state) do
    state.subscribers |> Bunch.KVList.each_key(&send_ratio(&1, ratio))
    %{state | ratio: ratio}
  end

  defp send_ratio(pid, ratio), do: send(pid, {:membrane_clock_ratio, self(), ratio})
end
