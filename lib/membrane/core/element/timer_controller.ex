defmodule Membrane.Core.Element.TimerController do
  @moduledoc false
  use Bunch
  use Membrane.Core.Element.Log
  require Membrane.Element.CallbackContext.Tick
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, Timer}
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext

  def start_timer(interval, clock, id, state) do
    if state.synchronization.timers |> Map.has_key?(id) do
      {{:error, {:timer_already_exists, id: id}}, state}
    else
      clock |> Clock.subscribe()
      timer = Timer.start(id, interval, clock)
      state |> Bunch.Access.put_in([:synchronization, :timers, id], timer) ~> {:ok, &1}
    end
  end

  def stop_timer(id, state) do
    {timer, state} = state |> Bunch.Access.pop_in([:synchronization, :timers, id])

    if timer |> is_nil do
      {{:error, {:unknown_timer, id}}, state}
    else
      :ok = timer |> Timer.stop()
      timer.clock |> Clock.unsubscribe()
      {:ok, state}
    end
  end

  def handle_tick(timer_id, %State{} = state) do
    context = &CallbackContext.Tick.from_state/1

    with true <- state.timers |> Map.has_key?(timer_id),
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_tick,
             ActionHandler,
             %{context: context},
             [timer_id],
             state
           ) do
      state
      |> Bunch.Access.update_in([:synchronization, :timers, timer_id], &Timer.tick/1)
      ~> {:ok, &1}
    else
      {{:error, reason}, state} ->
        warn_error("Error while handling tick", reason, state)

      false ->
        {:ok, state}
    end
  end

  def handle_clock_update(clock, ratio, state) do
    state
    |> update_in(
      [:synchronization, :timers],
      &Bunch.Map.map_values(&1, fn
        %Timer{clock: ^clock} = timer -> timer |> Timer.update_ratio(ratio)
        timer -> timer
      end)
    )
    ~> {:ok, &1}
  end
end
