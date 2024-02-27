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

  test "queue sorts buffers some buffers from different pads based on buffer dts" do
    input_order = [9, 4, 7, 3, 1, 8, 5, 6, 2, 0]

    pad_generator = fn i -> Pad.ref(:input, i) end
    buffer_generator = fn i -> %Buffer{dts: i, payload: <<>>} end

    queue =
      input_order
      |> Enum.reduce(TimestampQueue.new(), fn i, queue ->
        assert {[], queue} =
                 TimestampQueue.push_buffer(queue, pad_generator.(i), buffer_generator.(i))

        queue
      end)

    old_queue = queue

    # assert that queue won't pop last buffer from pad queue, if it hasn't recevied EoS on this pad
    assert {[], [], ^old_queue} = TimestampQueue.pop_batch(queue)

    queue =
      input_order
      |> Enum.reduce(queue, fn i, queue ->
        TimestampQueue.push_end_of_stream(queue, pad_generator.(i))
      end)

    assert {[], batch, queue} = TimestampQueue.pop_batch(queue)

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

    assert batch == expected_batch |> IO.inspect()

    # assert queue empty
    assert queue.pad_queues == TimestampQueue.new().pad_queues
    assert queue.pads_heap == TimestampQueue.new().pads_heap
  end

  defmodule StreamFormat do
    defstruct [:dts]
  end

  defmodule Event do
    defstruct [:dts]
  end

  test "queue sorts buffers a lot of buffers from different pads based on buffer dts" do
    pads_number = 100
    pad_items_number = 200

    dts_offsets = Map.new(1..pads_number, fn pad_idx ->
      {Pad.ref(:input, pad_idx), Enum.random(1..10_000)}
    end)

    pads_items =
      Map.new(1..pads_number, fn pad_idx ->
        pad_ref = Pad.ref(:input, pad_idx)
        dts_offset = dts_offsets[pad_ref]

        items =
          Enum.map_reduce(dts_offset..(dts_offset + pad_items_number - 1), 0, fn idx, last_buffer_dts ->
            Enum.random([
              {{:push_buffer, %Buffer{dts: idx, payload: <<>>}}, idx},
              {{:push_event, %Event{dts: last_buffer_dts}}, last_buffer_dts},
              {{:push_stream_format, %StreamFormat{dts: last_buffer_dts}}, last_buffer_dts}
            ])
          end)

        {pad_ref, items}
      end)

    queue = TimestampQueue.new()

    {pads_items, queue} =
      1..(pads_number * pad_items_number)
      |> Enum.reduce({pads_items, queue}, fn _i, {pads_items, queue} ->
        {pad_ref, items} = Enum.random(pads_items)
        [{fun_name, item} | items] = items

        pads_items =
          case items do
            [] -> Map.delete(pads_items, pad_ref)
            items -> Map.put(pads_items, pad_ref, items)
          end

        queue =
          case apply(TimestampQueue, fun_name, [queue, pad_ref, item]) do
            # if buffer
            {[], queue} -> queue
            # if event or stream_format
            queue -> queue
          end

        {pads_items, queue}
      end)

    queue = Enum.reduce(1..pads_number, queue, fn i, queue ->
      TimestampQueue.push_end_of_stream(queue, Pad.ref(:input, i))
    end)

    # sanity check, if the test is written correctly
    assert %{} = pads_items

    assert {[], batch, queue} = TimestampQueue.pop_batch(queue)
    assert length(batch) == pads_number * pad_items_number + pads_number

    batch_without_eos = Enum.reject(batch, &match?({_pad_ref, :end_of_stream}, &1))

    sorted_batch_without_eos =
      Enum.sort_by(batch_without_eos, fn {pad_ref, {_type, item}} -> item.dts end)

    assert batch_without_eos == sorted_batch_without_eos
  end
end
