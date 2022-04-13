defmodule Membrane.Core.TimerController do
  @moduledoc false
  use Bunch
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, Component, Timer}

  require Membrane.Core.Component
  require Membrane.Element.CallbackContext.Tick

  @spec start_timer(Timer.id_t(), Timer.interval_t(), Clock.t(), Component.state_t()) ::
          Component.state_t()
  def start_timer(id, interval, clock, state) do
    if state.synchronization.timers |> Map.has_key?(id) do
      raise Membrane.TimerError, "Timer #{inspect(id)} already exists"
    else
      clock |> Clock.subscribe()
      timer = Timer.start(id, interval, clock)
      put_in(state, [:synchronization, :timers, id], timer)
    end
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

  @spec stop_timer(Timer.id_t(), Component.state_t()) :: Component.state_t()
  def stop_timer(id, state) do
    {timer, state} = state |> Bunch.Access.pop_in([:synchronization, :timers, id])

    if timer |> is_nil do
      raise Membrane.TimerError, "Timer #{inspect(id)} doesn't exist"
    else
      :ok = timer |> Timer.stop()
      timer.clock |> Clock.unsubscribe()
      state
    end
  end

  @spec handle_tick(Timer.id_t(), Component.state_t()) :: Component.state_t()
  def handle_tick(timer_id, state) do
    context = Component.callback_context_generator(:any, Tick, state)

    # the first clause checks if the timer wasn't removed before receiving this tick
    with true <- Map.has_key?(state.synchronization.timers, timer_id),
         state =
           CallbackHandler.exec_and_handle_callback(
             :handle_tick,
             Component.action_handler(state),
             %{context: context},
             [timer_id],
             state
           ),
         # in case the timer was removed in handle_tick
         true <- Map.has_key?(state.synchronization.timers, timer_id) do
      update_in(state, [:synchronization, :timers, timer_id], &Timer.tick/1)
    else
      false -> state
    end
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
end
