defmodule Membrane.TimestampQueueTest do
  alias Membrane.TimestampQueue
  alias Membrane.Buffer

  require Membrane.Pad, as: Pad

  use ExUnit.Case, async: true

  test "queue raises on buffer with nil dts" do
    assert_raise(RuntimeError, fn ->
      TimestampQueue.new()
      |> TimestampQueue.push_buffer(:input, %Buffer{dts: nil, payload: <<>>})
    end)
  end

  test "queue sorts buffers from different pads based on buffer dts" do
    input_order = [9,4,7,3,1,8,5,6,2,0]

    pad_generator = fn i -> Pad.ref(:input, i) end
    buffer_generator = fn i -> %Buffer{dts: i, payload: <<>>} end

    queue =
      input_order
      |> Enum.reduce(TimestampQueue.new(), fn i, queue ->
        assert {[], queue} =
          queue
          |> TimestampQueue.push_buffer(pad_generator.(i), buffer_generator.(i))
          |> TimestampQueue.push_end_of_stream(pad_generator.(i))

        queue
      end)

    assert {[], batch, queue} = TimestampQueue.pop_batch(queue)

    # assert queue empty
    assert queue.pad_queues == TimestampQueue.new().pad_queues
    assert queue.pads_heap == TimestampQueue.new().pads_heap

    # assert batch
    expected_batch =
      input_order
      |> Enum.sort()
      |> Enum.flat_map(fn i ->
        [
          {pad_generator.(i), {:buffer, buffer_generator.(i)}},
          {pad_generator.(i), :end_of_stream}
        ]
      end)

    assert batch == expected_batch
  end
end
