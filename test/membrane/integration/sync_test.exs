defmodule Membrane.Integration.SyncTest do
  use ExUnit.Case, async: false

  alias Membrane.Support.Sync
  alias Membrane.{Time, Testing}

  @error 8
  @timeout 500

  @tag :long_running
  test "When ration = 1 amount of lost ticks is roughly the same regardless of the time of transmission" do
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

  defp receive_ticks(pipeline, amount \\ 0) do
    receive do
      :tick -> receive_ticks(pipeline, amount + 1)
    after
      @timeout -> amount
    end
  end
end
