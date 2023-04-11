defmodule Membrane.APIBackCompabilityTest do
  # this module tests if API in membrane_core v0.12 has no breaking changes comparing to api in v0.11
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.Testing

  test "if action :remove_child works" do
    defmodule Filter do
      use Membrane.Filter
    end

    pipeline = Testing.Pipeline.start_link_supervised!(spec: child(:filter, Filter))
    Process.sleep(100)
    filter_pid = Testing.Pipeline.get_child_pid!(pipeline, :filter)
    monitor_ref = Process.monitor(filter_pid)
    Testing.Pipeline.execute_actions(pipeline, remove_child: :filter)

    assert_receive {:DOWN, ^monitor_ref, _process, _pid, :normal}

    Testing.Pipeline.terminate(pipeline)
  end

  test "if `Membrane.Time.round_to_*` functions work" do
    module = Membrane.Time

    for {old_function, new_function} <- [
          round_to_days: :as_days,
          round_to_hours: :as_hours,
          round_to_minutes: :as_minutes,
          round_to_seconds: :as_seconds,
          round_to_milliseconds: :as_milliseconds,
          round_to_microseconds: :as_microseconds,
          round_to_nanoseconds: :as_nanoseconds
        ],
        timestamp_generator <- [:days, :microseconds] do
      timestamp = apply(module, timestamp_generator, [3])

      old_function_result = apply(module, old_function, [timestamp])
      new_function_result = apply(module, new_function, [timestamp, :round])

      assert old_function_result == new_function_result
    end

    timestamp = Membrane.Time.days(15) + Membrane.Time.nanoseconds(13)
    timebase = Membrane.Time.milliseconds(2)

    assert Membrane.Time.round_to_timebase(timestamp, timebase) ==
             Membrane.Time.divide_by_timebase(timestamp, timebase)
  end
end
