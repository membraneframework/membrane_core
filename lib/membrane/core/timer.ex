defmodule Membrane.Core.Timer do
  @moduledoc false
  alias Membrane.Clock
  alias Membrane.Core.Message
  alias Membrane.Time

  require Membrane.Core.Message

  @type id_t :: any()
  @type interval_t :: Ratio.t() | non_neg_integer | :no_interval
  @type t :: %__MODULE__{
          id: id_t,
          interval: interval_t,
          init_time: Time.t(),
          clock: Clock.t(),
          time_passed: Time.t(),
          ratio: Clock.ratio_t(),
          timer_ref: reference() | nil
        }

  @enforce_keys [:interval, :clock, :init_time, :id]
  defstruct @enforce_keys ++ [time_passed: 0, ratio: 1, timer_ref: nil]

  @spec start(id_t, interval_t, Clock.t()) :: t
  def start(id, interval, clock) do
    %__MODULE__{id: id, interval: interval, init_time: Time.monotonic_time(), clock: clock}
    |> tick
  end

  @spec stop(t) :: :ok
  def stop(timer) do
    Process.cancel_timer(timer.timer_ref)
    :ok
  end

  @spec update_ratio(t, Clock.ratio_t()) :: t
  def update_ratio(timer, ratio) do
    %__MODULE__{timer | ratio: ratio}
  end

  @spec tick(t) :: t
  def tick(%__MODULE__{interval: :no_interval} = timer) do
    timer
  end

  def tick(timer) do
    use Numbers, overload_operators: true

    %__MODULE__{
      id: id,
      interval: interval,
      init_time: init_time,
      time_passed: time_passed,
      ratio: ratio
    } = timer

    time_passed = time_passed + interval

    time =
      (init_time + Ratio.new(time_passed, ratio)) |> Ratio.floor() |> Time.round_to_milliseconds()

    timer_ref = Process.send_after(self(), Message.new(:timer_tick, id), time, abs: true)
    %__MODULE__{timer | time_passed: time_passed, timer_ref: timer_ref}
  end

  @spec set_interval(t, interval_t) :: t
  def set_interval(%__MODULE__{interval: :no_interval} = timer, interval) do
    tick(%__MODULE__{timer | interval: interval})
  end

  def set_interval(timer, interval) do
    %__MODULE__{timer | interval: interval}
  end
end
