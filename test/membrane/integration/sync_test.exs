defmodule Membrane.Integration.SyncTest do
  use ExUnit.Case, async: false

  alias Membrane.Support.Sync
  alias Membrane.{Time, Testing}

  @error 8
  @timeout 500

  @tag :long_running
  test "When ratio = 1 amount of lost ticks is roughly the same regardless of the time of transmission" do
    tick_interval = 1

    assert {:ok, pipeline} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               elements: [
                 source: %Sync.Source{
                   tick_interval: tick_interval |> Time.milliseconds(),
                   test_process: self()
                 },
                 sink: Sync.Sink
               ]
             })

    for tries <- [100, 1000, 10000] do
      Testing.Pipeline.play(pipeline)

      Process.sleep(tick_interval * tries)

      Testing.Pipeline.stop(pipeline)

      ticks_amount = receive_ticks(pipeline)

      assert_in_delta ticks_amount, tries, @error
    end
  end

  @tag :long_running
  test "Ratio modifies ticking pace correctly" do
    tick_interval = 100
    tries = 300
    ratio_error = 0.05

    actual_report_interval = 100
    reported_interval = 300

    assert {:ok, pipeline} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               elements: [
                 source: %Sync.Source{
                   tick_interval: tick_interval |> Time.milliseconds(),
                   test_process: self()
                 },
                 sink: Sync.Sink
               ]
             })

    %{clock_provider: %{clock: original_clock, provider: :sink}} = :sys.get_state(pipeline)

    Testing.Pipeline.play(pipeline)

    for _ <- 1..tries do
      send(original_clock, {:membrane_clock_update, reported_interval})
      Process.sleep(actual_report_interval)
    end

    Testing.Pipeline.stop(pipeline)

    ticks_amount = receive_ticks(pipeline)

    actual_test_time = tries * actual_report_interval
    expected_ratio = 3.0
    actual_tick_time = actual_test_time / ticks_amount

    assert_in_delta actual_tick_time / tick_interval, expected_ratio, ratio_error
  end

  defp receive_ticks(pipeline, amount \\ 0) do
    receive do
      :tick -> receive_ticks(pipeline, amount + 1)
    after
      @timeout -> amount
    end
  end
end
