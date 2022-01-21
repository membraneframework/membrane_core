defmodule Membrane.Core.Element.InputQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Element.InputQueue

  describe "take_and_demand" do
    setup do
      input_queue =
        InputQueue.init(%{
          demand_unit: :buffers,
          demand_pid: self(),
          demand_pad: :pad,
          log_tag: "test",
          toilet?: false,
          demand_excess: nil,
          min_demand_factor: nil
        })

      assert_receive {Membrane.Core.Message, :demand, 40, [for_pad: :pad]}

      [input_queue: input_queue]
    end

    test "returns {:empty, []} when the queue is empty", %{input_queue: input_queue} do
      assert {{:empty, []}, %InputQueue{size: 0, demand: 0}} =
               InputQueue.take_and_demand(input_queue, 1, self(), :input)

      refute_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}
    end

    test "sends demands to the pid and updates demand", %{input_queue: input_queue} do
      assert {{:value, [{:buffers, [1], 1}]}, new_input_queue} =
               input_queue
               |> InputQueue.store(bufs(10))
               |> InputQueue.take_and_demand(1, self(), :pad)

      assert_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}

      assert new_input_queue.size == 9
      assert new_input_queue.demand == -9
    end
  end

  defp bufs(n), do: Enum.to_list(1..n)
end
