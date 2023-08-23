defmodule Membrane.Core.TimerController do
  @moduledoc false
  use Bunch
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, Component, Timer}

  require Membrane.Core.Component

  defguardp is_timer_present(timer_id, state)
            when is_map_key(state.synchronization.timers, timer_id)

  @spec start_timer(Timer.id(), Timer.interval(), Clock.t(), Component.state()) ::
          Component.state()
  def start_timer(id, _interval, _clock, state) when is_timer_present(id, state) do
    raise Membrane.TimerError, "Timer #{inspect(id)} already exists"
  end

  def start_timer(id, interval, clock, state) do
    clock |> Clock.subscribe()
    timer = Timer.start(id, interval, clock)
    put_in(state, [:synchronization, :timers, id], timer)
  end

  @spec timer_interval(Timer.id(), Timer.interval(), Component.state()) ::
          Component.state()
  def timer_interval(id, interval, state) do
    with {:ok, timer} <- state.synchronization.timers |> Map.fetch(id) do
      put_in(
        state,
        [:synchronization, :timers, id],
        Timer.set_interval(timer, interval)
      )
    else
      :error -> raise Membrane.TimerError, "Timer #{inspect(id)} doesn't exist"
    end
  end

  @spec stop_all_timers(Component.state()) :: Component.state()
  def stop_all_timers(state) do
    for {_id, timer} <- state.synchronization.timers do
      stop_and_unsubscribe(timer)
    end

    put_in(state, [:synchronization, :timers], %{})
  end

  @spec stop_timer(Timer.id(), Component.state()) :: Component.state()
  def stop_timer(id, state) do
    {timer, state} = state |> pop_in([:synchronization, :timers, id])

    if timer |> is_nil do
      raise Membrane.TimerError, "Timer #{inspect(id)} doesn't exist"
    else
      stop_and_unsubscribe(timer)
      state
    end
  end

  @spec handle_tick(Timer.id(), Component.state()) :: Component.state()
  def handle_tick(timer_id, state) when is_timer_present(timer_id, state) do
    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_tick,
        Component.action_handler(state),
        %{context: &Component.context_from_state/1},
        [timer_id],
        state
      )

    # in case the timer was removed in handle_tick
    if is_timer_present(timer_id, state) do
      update_in(state, [:synchronization, :timers, timer_id], &Timer.tick/1)
    else
      state
    end
  end

  def handle_tick(_timer_id, state) do
    state
  end

  @spec handle_clock_update(Timer.id(), Clock.ratio(), Component.state()) ::
          Component.state()
  def handle_clock_update(clock, ratio, state) do
    update_in(
      state,
      [:synchronization, :timers],
      &Bunch.Map.map_values(&1, fn
        %Timer{clock: ^clock} = timer -> timer |> Timer.update_ratio(ratio)
        timer -> timer
      end)
    )
  end

  @spec stop_and_unsubscribe(Timer.t()) :: :ok
  defp stop_and_unsubscribe(timer) do
    Timer.stop(timer)
    Clock.unsubscribe(timer.clock)
  end
end
