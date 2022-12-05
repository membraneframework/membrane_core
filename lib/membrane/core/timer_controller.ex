defmodule Membrane.Core.TimerController do
  @moduledoc false
  use Bunch
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, Component, Timer}

  require Membrane.Core.Component
  require Membrane.Element.CallbackContext.Tick

  defguardp is_timer_present(timer_id, state)
            when is_map_key(state.synchronization.timers, timer_id)

  @spec start_timer(Timer.id_t(), Timer.interval_t(), Clock.t(), Component.state_t()) ::
          Component.state_t()
  def start_timer(id, _interval, _clock, state) when is_timer_present(id, state) do
    raise Membrane.TimerError, "Timer #{inspect(id)} already exists"
  end

  def start_timer(id, interval, clock, state) do
    clock |> Clock.subscribe()
    timer = Timer.start(id, interval, clock)
    put_in(state, [:synchronization, :timers, id], timer)
  end

  @spec timer_interval(Timer.id_t(), Timer.interval_t(), Component.state_t()) ::
          Component.state_t()
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

  @spec stop_all_timers(Component.state_t()) :: Component.state_t()
  def stop_all_timers(state) do
    for {_id, timer} <- state.synchronization.timers do
      stop_and_unsubscribe(timer)
    end

    Bunch.Access.put_in(state, [:synchronization, :timers], %{})
  end

  @spec stop_timer(Timer.id_t(), Component.state_t()) :: Component.state_t()
  def stop_timer(id, state) do
    {timer, state} = state |> Bunch.Access.pop_in([:synchronization, :timers, id])

    if timer |> is_nil do
      raise Membrane.TimerError, "Timer #{inspect(id)} doesn't exist"
    else
      stop_and_unsubscribe(timer)
      state
    end
  end

  @spec handle_tick(Timer.id_t(), Component.state_t()) :: Component.state_t()
  def handle_tick(timer_id, state) when is_timer_present(timer_id, state) do
    context = Component.callback_context_generator(:any, Tick, state)

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_tick,
        Component.action_handler(state),
        %{context: context},
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

  @spec handle_clock_update(Timer.id_t(), Clock.ratio_t(), Component.state_t()) ::
          Component.state_t()
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
