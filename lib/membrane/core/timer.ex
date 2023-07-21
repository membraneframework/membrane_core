defmodule Membrane.Core.Timer do
  @moduledoc false
  alias Membrane.Clock
  alias Membrane.Core.Message
  alias Membrane.Time

  require Membrane.Core.Message

  @type id :: any()
  @type interval :: Ratio.t() | Time.non_neg() | :no_interval
  @type t :: %__MODULE__{
          id: id,
          interval: interval,
          init_time: Time.t(),
          clock: Clock.t(),
          next_tick_time: Time.t(),
          ratio: Clock.ratio(),
          timer_ref: reference() | nil
        }

  @enforce_keys [:interval, :clock, :init_time, :id]
  defstruct @enforce_keys ++
              [
                next_tick_time: 0,
                ratio: %Ratio{denominator: 1, numerator: 1},
                timer_ref: nil
              ]

  @spec start(id, interval, Clock.t()) :: t
  def start(id, interval, clock) do
    %__MODULE__{id: id, interval: interval, init_time: Time.monotonic_time(), clock: clock}
    |> tick
  end

  @spec stop(t) :: :ok
  def stop(%__MODULE__{interval: :no_interval}) do
    :ok
  end

  def stop(%__MODULE__{timer_ref: timer_ref}) do
    _time_left = Process.cancel_timer(timer_ref)
    :ok
  end

  @spec update_ratio(t, Clock.ratio()) :: t
  def update_ratio(timer, ratio) do
    %__MODULE__{timer | ratio: ratio}
  end

  @spec tick(t) :: t
  def tick(%__MODULE__{interval: :no_interval} = timer) do
    timer
  end

  def tick(timer) do
    use Ratio

    %__MODULE__{
      id: id,
      interval: interval,
      init_time: init_time,
      next_tick_time: next_tick_time,
      ratio: ratio
    } = timer

    next_tick_time = next_tick_time + interval

    # Next tick time converted to BEAM clock time
    beam_next_tick_time =
      Ratio.add(Ratio.new(init_time), Ratio.div(next_tick_time, ratio))
      |> Ratio.floor()
      |> Time.as_milliseconds(:round)

    timer_ref =
      Process.send_after(self(), Message.new(:timer_tick, id), beam_next_tick_time, abs: true)

    %__MODULE__{timer | next_tick_time: next_tick_time, timer_ref: timer_ref}
  end

  @spec set_interval(t, interval) :: t
  def set_interval(%__MODULE__{interval: :no_interval} = timer, interval) do
    %__MODULE__{timer | interval: interval}
    |> tick()
  end

  def set_interval(timer, interval) do
    %__MODULE__{timer | interval: interval}
  end
end
