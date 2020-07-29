defmodule Membrane.Core.Element.TimerController do
  @moduledoc false
  use Bunch
  require Membrane.Element.CallbackContext.Tick
  alias Membrane.Clock
  alias Membrane.Core.{CallbackHandler, Timer}
  alias Membrane.Core.Element.{ActionHandler, State}
  alias Membrane.Element.CallbackContext

  @spec start_timer(Timer.id_t(), Timer.interval_t(), Clock.t(), State.t()) ::
          {:ok, State.t()} | {{:error, {:timer_already_exists, id: Timer.id_t()}}, State.t()}
  def start_timer(id, interval, clock, state) do
    if state.synchronization.timers |> Map.has_key?(id) do
      {{:error, {:timer_already_exists, id: id}}, state}
    else
      clock |> Clock.subscribe()
      timer = Timer.start(id, interval, clock)
      state |> Bunch.Access.put_in([:synchronization, :timers, id], timer) ~> {:ok, &1}
    end
  end

  @spec timer_interval(Timer.id_t(), Timer.interval_t(), State.t()) ::
          {:ok, State.t()} | {{:error, {:unknown_timer, id: Timer.id_t()}}, State.t()}
  def timer_interval(id, interval, state) do
    with {:ok, timer} <- state.synchronization.timers |> Map.fetch(id) do
      Bunch.Access.put_in(
        state,
        [:synchronization, :timers, id],
        Timer.set_interval(timer, interval)
      )
      ~> {:ok, &1}
    else
      :error -> {{:error, {:unknown_timer, id}}, state}
    end
  end

  @spec stop_timer(Timer.id_t(), State.t()) ::
          {:ok, State.t()} | {{:error, {:unknown_timer, id: Timer.id_t()}}, State.t()}
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

  @spec handle_tick(Timer.id_t(), State.t()) :: {:ok, State.t()} | {{:error, any}, State.t()}
  def handle_tick(timer_id, %State{} = state) do
    context = &CallbackContext.Tick.from_state/1

    withl present?: true <- Map.has_key?(state.synchronization.timers, timer_id),
          callback:
            {:ok, state} <-
              CallbackHandler.exec_and_handle_callback(
                :handle_tick,
                ActionHandler,
                %{context: context},
                [timer_id],
                state
              ),
          present?: true <- Map.has_key?(state.synchronization.timers, timer_id) do
      state
      |> Bunch.Access.update_in([:synchronization, :timers, timer_id], &Timer.tick/1)
      ~> {:ok, &1}
    else
      present?: false -> {:ok, state}
      callback: {{:error, _reason}, _state} = err -> err
    end
  end

  @spec handle_clock_update(Timer.id_t(), Clock.ratio_t(), State.t()) :: {:ok, State.t()}
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
