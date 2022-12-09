defmodule Membrane.Integration.SyncTest.TickingPace do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec

  alias Membrane.Support.Sync
  alias Membrane.{Testing, Time}

  @tag :long_running
  test "Ratio modifies ticking pace correctly" do
    tick_interval = 100
    tries = 300
    ratio_error = 0.1

    actual_report_interval = 100
    reported_interval = 300

    links = [
      child(:source, %Sync.Source{
        tick_interval: tick_interval |> Time.milliseconds(),
        test_process: self()
      })
      |> child(:sink, Sync.Sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: links)

    %{synchronization: %{clock_provider: %{clock: original_clock, provider: :sink}}} =
      :sys.get_state(pipeline)

    for _ <- 1..tries do
      send(original_clock, {:membrane_clock_update, reported_interval})
      Process.sleep(actual_report_interval)
    end

    Testing.Pipeline.terminate(pipeline)

    ticks_amount = Sync.Helper.receive_ticks()

    actual_test_time = tries * actual_report_interval
    expected_ratio = 3.0
    actual_tick_time = actual_test_time / ticks_amount

    assert_in_delta tick_interval / actual_tick_time, expected_ratio, ratio_error
  end
end
