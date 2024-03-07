defmodule Membrane.TimestampQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.TimestampQueue

  require Membrane.Pad, as: Pad

  test "queue raises on buffer with nil dts" do
    assert_raise(RuntimeError, fn ->
      TimestampQueue.new()
      |> TimestampQueue.push_buffer(:input, %Buffer{dts: nil, payload: <<>>})
    end)
  end

  test "queue sorts some buffers from different pads based on buffer dts" do
    input_order = [9, 4, 7, 3, 1, 8, 5, 6, 2, 10]

    pad_generator = fn i -> Pad.ref(:input, i) end
    buffer_generator = fn i -> %Buffer{dts: i, payload: <<>>} end

    queue =
      input_order
      |> Enum.reduce(TimestampQueue.new(), fn i, queue ->
        assert {[], queue} =
                 TimestampQueue.push_buffer(queue, pad_generator.(i), %Buffer{
                   dts: 0,
                   payload: <<>>
                 })

        queue
      end)

    queue =
      input_order
      |> Enum.reduce(queue, fn i, queue ->
        assert {[], queue} =
                 TimestampQueue.push_buffer(queue, pad_generator.(i), buffer_generator.(i))

        queue
      end)

    # assert that queue won't pop last buffer from pad queue, if it hasn't recevied EoS on this pad
    assert {[], batch, queue} = TimestampQueue.pop_batch(queue)

    Enum.each(batch, fn item ->
      assert {_pad_ref, {:buffer, %Buffer{dts: 0}}} = item
    end)

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

    assert batch == expected_batch

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

    dts_offsets =
      Map.new(1..pads_number, fn pad_idx ->
        {Pad.ref(:input, pad_idx), Enum.random(1..10_000)}
      end)

    pads_items =
      Map.new(1..pads_number, fn pad_idx ->
        pad_ref = Pad.ref(:input, pad_idx)
        dts_offset = dts_offsets[pad_ref]

        {items, _last_buffer_dts} =
          Enum.map_reduce(dts_offset..(dts_offset + pad_items_number - 1), dts_offset, fn idx,
                                                                                          last_buffer_dts ->
            if idx == dts_offset do
              {{:push_buffer, %Buffer{dts: idx, payload: <<>>}}, idx}
            else
              Enum.random([
                {{:push_buffer, %Buffer{dts: idx, payload: <<>>}}, idx},
                {{:push_event, %Event{dts: last_buffer_dts}}, last_buffer_dts},
                {{:push_stream_format, %StreamFormat{dts: last_buffer_dts}}, last_buffer_dts}
              ])
            end
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

    queue =
      Enum.reduce(1..pads_number, queue, fn i, queue ->
        TimestampQueue.push_end_of_stream(queue, Pad.ref(:input, i))
      end)

    # sanity check, that test is written correctly
    assert %{} = pads_items

    assert {[], batch, _queue} = TimestampQueue.pop_batch(queue)
    assert length(batch) == pads_number * pad_items_number + pads_number

    batch_without_eos = Enum.reject(batch, &match?({_pad_ref, :end_of_stream}, &1))

    sorted_batch_without_eos =
      batch_without_eos
      |> Enum.sort_by(fn {pad_ref, {_type, item}} -> item.dts - dts_offsets[pad_ref] end)

    assert batch_without_eos == sorted_batch_without_eos
  end

  test "queue prioritizes stream formats and buffers not preceded by a buffer" do
    queue = TimestampQueue.new()

    {[], queue} = TimestampQueue.push_buffer(queue, :a, %Buffer{dts: 1, payload: <<>>})
    {[], queue} = TimestampQueue.push_buffer(queue, :a, %Buffer{dts: 2, payload: <<>>})

    assert {[], [a: {:buffer, %Buffer{dts: 1}}], queue} = TimestampQueue.pop_batch(queue)

    {[], queue} = TimestampQueue.push_buffer(queue, :a, %Buffer{dts: 3, payload: <<>>})
    queue = TimestampQueue.push_end_of_stream(queue, :a)

    queue = TimestampQueue.push_stream_format(queue, :b, %StreamFormat{})
    queue = TimestampQueue.push_event(queue, :b, %Event{})

    assert {[], batch, queue} = TimestampQueue.pop_batch(queue)

    assert batch == [
             b: {:stream_format, %StreamFormat{}},
             b: {:event, %Event{}},
             a: {:buffer, %Buffer{dts: 2, payload: <<>>}},
             a: {:buffer, %Buffer{dts: 3, payload: <<>>}},
             a: :end_of_stream
           ]

    assert {[], [], ^queue} = TimestampQueue.pop_batch(queue)
  end

  [
    %{unit: :buffers, buffer_size: 1, buffer: %Buffer{dts: 0, payload: <<>>}},
    %{unit: :bytes, buffer_size: 100, buffer: %Buffer{dts: 0, payload: <<1::8*100>>}}
  ]
  |> Enum.map(fn params ->
    test "queue returns proper suggested actions when boundary unit is #{inspect(params.unit)}" do
      %{unit: unit, buffer_size: buffer_size, buffer: buffer} =
        unquote(Macro.escape(params))

      boundary_in_buff_no = 100
      boundary = buffer_size * boundary_in_buff_no

      queue =
        TimestampQueue.new(
          pause_demand_boundary: boundary,
          pause_demand_boundary_unit: unit
        )

      queue =
        1..(boundary_in_buff_no - 1)
        |> Enum.reduce(queue, fn _i, queue ->
          assert {[], queue} = TimestampQueue.push_buffer(queue, :input, buffer)
          queue
        end)

      assert {[pause_auto_demand: :input], queue} =
               TimestampQueue.push_buffer(queue, :input, buffer)

      queue =
        1..(boundary_in_buff_no - 1)
        |> Enum.reduce(queue, fn _i, queue ->
          assert {[], queue} = TimestampQueue.push_buffer(queue, :input, buffer)
          queue
        end)

      pop_item = {:input, {:buffer, buffer}}

      expected_batch = for _i <- 1..(2 * boundary_in_buff_no - 2), do: pop_item

      assert {[resume_auto_demand: :input], ^expected_batch, _queue} =
               TimestampQueue.pop_batch(queue)
    end
  end)

  test "queue sorts buffers from various pads when they aren't linked in the same moment" do
    iteration_size = 100
    iterations = 100

    1..iterations
    |> Enum.reduce(TimestampQueue.new(), fn pads_in_iteration, queue ->
      pads = for i <- 1..pads_in_iteration, do: Pad.ref(:input, i)
      new_pad = Pad.ref(:input, pads_in_iteration)

      queue =
        Enum.reduce([0, 1], queue, fn timestamp, queue ->
          timestamp_field = if div(pads_in_iteration, 2) == 1, do: :dts, else: :pts

          buffer =
            %Buffer{payload: <<>>}
            |> Map.put(timestamp_field, timestamp)

          {[], queue} = TimestampQueue.push_buffer(queue, new_pad, buffer)
          queue
        end)

      queue =
        pads
        |> Enum.reduce(queue, fn pad_ref, queue ->
          Pad.ref(:input, pad_idx) = pad_ref
          pad_offset = iteration_size * (pads_in_iteration - pad_idx) + 2
          timestamp_field = if div(pad_idx, 2) == 1, do: :dts, else: :pts

          pad_offset..(pad_offset + iteration_size - 1)
          |> Enum.reduce(queue, fn timestamp, queue ->
            buffer =
              %Buffer{payload: <<>>}
              |> Map.put(timestamp_field, timestamp)

            {[], queue} = TimestampQueue.push_buffer(queue, pad_ref, buffer)
            queue
          end)
        end)

      {[], batch, queue} = TimestampQueue.pop_batch(queue)

      sorted_batch =
        batch
        |> Enum.sort_by(fn {Pad.ref(:input, pad_idx), {:buffer, buffer}} ->
          (buffer.dts || buffer.pts) + pad_idx * iteration_size
        end)

      assert batch == sorted_batch

      queue
    end)
  end

  # todo: unify tests naming convention
  test "registering pads" do
    queue =
      TimestampQueue.new()
      |> TimestampQueue.wait_on_pad(:a)
      |> TimestampQueue.wait_on_pad(:b)

    events = for i <- 1..1000, do: %Event{dts: i}
    buffers = for i <- 1..1000, do: %Buffer{dts: i, payload: <<>>}

    queue =
      events
      |> Enum.reduce(queue, fn event, queue ->
        queue
        |> TimestampQueue.push_event(:a, event)
        |> TimestampQueue.push_event(:b, event)
      end)

    queue =
      buffers
      |> Enum.reduce(queue, fn buffer, queue ->
        {[], queue} = TimestampQueue.push_buffer(queue, :a, buffer)
        queue
      end)

    {[], batch, queue} = TimestampQueue.pop_batch(queue)

    grouped_batch = Enum.group_by(batch, &elem(&1, 0), &(elem(&1, 1) |> elem(1)))
    assert grouped_batch == %{a: events, b: events}

    assert {[], [], queue} = TimestampQueue.pop_batch(queue)

    queue =
      buffers
      |> Enum.reduce(queue, fn buffer, queue ->
        {[], queue} = TimestampQueue.push_buffer(queue, :b, buffer)
        queue
      end)

    {[], batch, _queue} = TimestampQueue.pop_batch(queue)

    sorted_batch = Enum.sort_by(batch, fn {_pad_ref, {:buffer, buffer}} -> buffer.dts end)
    assert batch == sorted_batch

    grouped_batch = Enum.group_by(batch, &elem(&1, 0), &(elem(&1, 1) |> elem(1)))

    assert grouped_batch == %{
             a: List.delete_at(buffers, 999),
             b: List.delete_at(buffers, 999)
           }
  end
end
