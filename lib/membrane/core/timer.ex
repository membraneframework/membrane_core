defmodule Membrane.Core.Timer do
  @moduledoc false
  require Membrane.Core.Message
  alias Membrane.Core.Message
  alias Membrane.Time
  alias Membrane.Clock

  @type id_t :: any()
  @type t :: %__MODULE__{
          id: any,
          interval: Time.t(),
          init_time: Time.t(),
          clock: Clock.t(),
          time_passed: Time.t(),
          ratio: Ratio.t(),
          timer_ref: reference() | nil
        }

  @enforce_keys [:interval, :clock, :init_time, :id]
  defstruct @enforce_keys ++ [time_passed: 0, ratio: 1, timer_ref: nil]

  def start(id, interval, clock) do
    %__MODULE__{id: id, interval: interval, init_time: Time.monotonic_time(), clock: clock}
    |> tick
  end

  def stop(timer) do
    Process.cancel_timer(timer.timer_ref)
    :ok
  end

  def update_ratio(timer, ratio) do
    %__MODULE__{timer | ratio: ratio}
  end

  def tick(timer) do
    use Ratio

    %__MODULE__{
      id: id,
      interval: interval,
      init_time: init_time,
      time_passed: time_passed,
      ratio: ratio
    } = timer

    time_passed = time_passed + interval
    time = (init_time + ratio * time_passed) |> Ratio.floor() |> Time.to_milliseconds()
    timer_ref = Process.send_after(self(), Message.new(:timer_tick, id), time, abs: true)
    %__MODULE__{timer | time_passed: time_passed, timer_ref: timer_ref}
  end
end
