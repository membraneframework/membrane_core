defmodule Membrane.Core.Element.TimerController do
  require Membrane.Core.Message
  require Membrane.Element.CallbackContext.Tick
  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext
  alias Membrane.Time

  @enforce_keys [:interval, :clock, :init_time]
  defstruct @enforce_keys ++ [time_passed: 0, ratio: 1, timer_ref: nil]

  def start_timer(interval, clock, id, state) do
    with false <- state.timers |> Map.has_key?(id) do
      state = state |> Bunch.Access.update_in([:timers_clocks, clock], &add_clock(&1, clock, id))

      timer =
        %__MODULE__{interval: interval, clock: clock, init_time: Time.monotonic_time()}
        |> tick(id, state.timers_clocks)

      state = state |> Bunch.Access.put_in([:timers, id], timer)

      {:ok, state}
    else
      true -> {{:error, {:timer_already_exists, id: id}}, state}
    end
  end

  def stop_timer(id, state) do
    {timer, state} = state |> Bunch.Access.pop_in([:timers, id])

    with false <- timer |> is_nil do
      Process.cancel_timer(timer.timer_ref)

      {clock_timers, state} =
        state
        |> Bunch.Access.get_updated_in([:timers_clocks, timer.clock, :timers], &MapSet.delete(&1, timer))

      state =
        if clock_timers |> Enum.empty?() do
          send(timer.clock, Message.new(:clock_unsubscribe, self()))
          state |> Bunch.Access.delete_in([:timers_clocks, timer.clock])
        else
          state
        end

      {:ok, state}
    else
      true -> {{:error, {:unknown_timer, id}}, state}
    end
  end

  def handle_tick(timer_id, %State{} = state) do
    context = &CallbackContext.Tick.from_state/1

    with true <- state.timers |> Map.has_key?(timer_id) or {:ok, state},
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_tick,
             ActionHandler,
             %{context: context},
             [timer_id],
             state
           ) do
      state =
        state |> Bunch.Access.update_in([:timers, timer_id], &tick(&1, timer_id, state.timers_clocks))

      {:ok, state}
    end
  end

  def handle_clock_update(clock, ratio, state) do
    state =
      if state.timers_clocks[clock] do
        state |> Bunch.Access.update_in([:timers_clocks, clock], &%{&1 | ratio: ratio})
      else
        state
      end

    {:ok, state}
  end

  defp add_clock(nil, clock, timer_id) do
    send(clock, Message.new(:clock_subscribe, self()))
    %{ratio: 1, timers: MapSet.new([timer_id])}
  end

  defp add_clock(clock_data, _clock, timer_id) do
    clock_data |> Map.update!(:timers, &MapSet.put(&1, timer_id))
  end

  defp tick(timer, timer_id, timers_clocks) do
    use Ratio

    %__MODULE__{
      interval: interval,
      init_time: init_time,
      time_passed: time_passed,
      clock: clock
    } = timer

    %{^clock => %{ratio: ratio}} = timers_clocks

    time_passed = time_passed + interval
    time = (init_time + ratio * time_passed) |> Ratio.floor() |> Time.to_milliseconds()
    timer_ref = Process.send_after(self(), Message.new(:timer_tick, timer_id), time, abs: true)
    %__MODULE__{timer | time_passed: time_passed, timer_ref: timer_ref}
  end
end
