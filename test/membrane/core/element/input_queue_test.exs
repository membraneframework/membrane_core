defmodule Membrane.Core.Element.InputQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Element.InputQueue
  alias Membrane.Core.Message
  alias Membrane.Testing.Event

  require Message

  describe ".init/6 should" do
    setup do
      {:ok,
       %{
         log_tag: "test",
         target_queue_size: 100,
         min_demand_factor: 0.1,
         input_demand_unit: :bytes,
         output_demand_unit: :bytes,
         demand_pid: self(),
         linked_output_ref: :output_pad_ref,
         expected_metric: Buffer.Metric.from_unit(:bytes),
         expected_min_demand: 10
       }}
    end

    test "return InputQueue struct and send demand message", context do
      assert InputQueue.init(%{
               input_demand_unit: context.input_demand_unit,
               output_demand_unit: context.output_demand_unit,
               demand_pid: context.demand_pid,
               demand_pad: context.linked_output_ref,
               log_tag: context.log_tag,
               toilet?: false,
               target_size: context.target_queue_size,
               min_demand_factor: context.min_demand_factor
             }) == %InputQueue{
               q: Qex.new(),
               log_tag: context.log_tag,
               target_size: context.target_queue_size,
               size: 0,
               demand: 0,
               min_demand: context.expected_min_demand,
               input_metric: context.expected_metric,
               output_metric: context.expected_metric,
               toilet?: false
             }

      message =
        Message.new(:demand, context.target_queue_size, for_pad: context.linked_output_ref)

      assert_received ^message
    end

    test "not send the demand if toilet is enabled", context do
      assert InputQueue.init(%{
               input_demand_unit: context.input_demand_unit,
               output_demand_unit: context.output_demand_unit,
               demand_pid: context.demand_pid,
               demand_pad: context.linked_output_ref,
               log_tag: context.log_tag,
               toilet?: true,
               target_size: context.target_queue_size,
               min_demand_factor: context.min_demand_factor
             }) == %InputQueue{
               q: Qex.new(),
               log_tag: context.log_tag,
               target_size: context.target_queue_size,
               size: 0,
               demand: context.target_queue_size,
               min_demand: context.expected_min_demand,
               input_metric: context.expected_metric,
               output_metric: context.expected_metric,
               toilet?: true
             }

      refute_received Message.new(:demand, _)
    end
  end

  describe ".empty?/1 should" do
    setup do
      buffer = %Buffer{payload: <<1, 2, 3>>}

      input_queue =
        struct(InputQueue,
          size: 0,
          input_metric: Buffer.Metric.Count,
          output_metric: Buffer.Metric.Count,
          q: Qex.new()
        )

      not_empty_input_queue = InputQueue.store(input_queue, :buffers, [buffer])

      {:ok,
       %{
         size: 0,
         buffer: buffer,
         input_queue: input_queue,
         not_empty_input_queue: not_empty_input_queue
       }}
    end

    test "return true when pull buffer is empty", context do
      assert InputQueue.empty?(context.input_queue) == true
    end

    test "return false when pull buffer contains some buffers ", context do
      assert InputQueue.empty?(context.not_empty_input_queue) == false
    end
  end

  describe ".store/3 should" do
    setup do
      {:ok, %{size: 10, q: Qex.new() |> Qex.push({:buffers, [], 3, 3}), payload: <<1, 2, 3>>}}
    end

    test "increment `size` when `:metric` is `Count`", context do
      input_queue =
        struct(InputQueue,
          size: context.size,
          input_metric: Buffer.Metric.Count,
          output_metric: Buffer.Metric.Count,
          q: context.q
        )

      v = [%Buffer{payload: context.payload}]
      %{size: new_size} = InputQueue.store(input_queue, :buffers, v)
      assert new_size == context.size + 1
    end

    test "add payload size to `size` when `:metric` is `ByteSize`", context do
      input_queue =
        struct(InputQueue,
          size: context.size,
          input_metric: Buffer.Metric.ByteSize,
          output_metric: Buffer.Metric.ByteSize,
          q: context.q
        )

      v = [%Buffer{payload: context.payload}]
      %{size: new_size} = InputQueue.store(input_queue, :buffers, v)
      assert new_size == context.size + byte_size(context.payload)
    end

    test "append buffer to the queue", context do
      input_queue =
        struct(InputQueue,
          size: context.size,
          input_metric: Buffer.Metric.ByteSize,
          output_metric: Buffer.Metric.ByteSize,
          q: context.q
        )

      v = [%Buffer{payload: context.payload}]
      %{q: new_q} = InputQueue.store(input_queue, :buffers, v)
      {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
      assert remaining_q == context.q
      assert last_elem == {:buffers, v, 3, 3}
    end

    test "append event to the queue", context do
      input_queue =
        struct(InputQueue,
          size: context.size,
          input_metric: Buffer.Metric.ByteSize,
          output_metric: Buffer.Metric.ByteSize,
          q: context.q
        )

      v = %Event{}
      %{q: new_q} = InputQueue.store(input_queue, :event, v)
      {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
      assert remaining_q == context.q
      assert last_elem == {:non_buffer, :event, v}
    end

    test "keep other fields unchanged after storing an event", context do
      input_queue =
        struct(InputQueue,
          size: context.size,
          input_metric: Buffer.Metric.ByteSize,
          output_metric: Buffer.Metric.ByteSize,
          q: context.q
        )

      v = %Event{}
      new_input_queue = InputQueue.store(input_queue, :event, v)
      assert %{new_input_queue | q: context.q} == input_queue
    end
  end

  describe ".take_and_demand/4 should" do
    setup do
      input_queue =
        InputQueue.init(%{
          input_demand_unit: :buffers,
          output_demand_unit: :buffers,
          demand_pid: self(),
          demand_pad: :pad,
          log_tag: "test",
          toilet?: false,
          target_size: nil,
          min_demand_factor: nil
        })

      assert_receive {Membrane.Core.Message, :demand, 40, [for_pad: :pad]}

      [input_queue: input_queue]
    end

    test "return {:empty, []} when the queue is empty", %{input_queue: input_queue} do
      assert {{:empty, []}, %InputQueue{size: 0, demand: 0}} =
               InputQueue.take_and_demand(input_queue, 1, self(), :input)

      refute_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}
    end

    test "send demands to the pid and updates demand", %{input_queue: input_queue} do
      assert {{:value, [{:buffers, [1], 1, 1}]}, new_input_queue} =
               input_queue
               |> InputQueue.store(bufs(10))
               |> InputQueue.take_and_demand(1, self(), :pad)

      assert_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}

      assert new_input_queue.size == 9
      assert new_input_queue.demand == -9
    end
  end

  describe ".take_and_demand/4 should also" do
    setup do
      size = 6
      buffers1 = {:buffers, [:b1, :b2, :b3], 3, 3}
      buffers2 = {:buffers, [:b4, :b5, :b6], 3, 3}
      q = Qex.new() |> Qex.push(buffers1) |> Qex.push(buffers2)

      input_queue =
        struct(InputQueue,
          size: size,
          demand: 0,
          min_demand: 0,
          target_queue_size: 100,
          toilet?: false,
          input_metric: Buffer.Metric.Count,
          output_metric: Buffer.Metric.Count,
          q: q
        )

      {:ok, %{input_queue: input_queue, q: q, size: size, buffers1: buffers1, buffers2: buffers2}}
    end

    test "return tuple {:ok, {:empty, buffers}} when there are not enough buffers",
         context do
      {result, _new_input_queue} =
        InputQueue.take_and_demand(
          context.input_queue,
          10,
          self(),
          :linked_output_ref
        )

      assert result == {:empty, [context.buffers1, context.buffers2]}
    end

    test "set `size` to 0 when there are not enough buffers", context do
      {_, %{size: new_size}} =
        InputQueue.take_and_demand(
          context.input_queue,
          10,
          self(),
          :linked_output_ref
        )

      assert new_size == 0
    end

    test "generate demand hen there are not enough buffers", context do
      InputQueue.take_and_demand(
        context.input_queue,
        10,
        self(),
        :linked_output_ref
      )

      expected_size = context.size
      pad_ref = :linked_output_ref
      message = Message.new(:demand, expected_size, for_pad: pad_ref)
      assert_received ^message
    end

    test "return `to_take` buffers from the queue when there are enough buffers and buffers dont have to be split",
         context do
      {result, %{q: new_q}} =
        InputQueue.take_and_demand(
          context.input_queue(),
          3,
          self(),
          :linked_output_ref
        )

      assert result == {:value, [context.buffers1()]}

      list = new_q |> Enum.into([])
      exp_list = Qex.new() |> Qex.push(context.buffers2()) |> Enum.into([])

      assert list == exp_list
      assert_received Message.new(:demand, _, _)
    end

    test "return `to_take` buffers from the queue when there are enough buffers and buffers have to be split",
         context do
      {result, %{q: new_q}} =
        InputQueue.take_and_demand(
          context.input_queue,
          4,
          self(),
          :linked_output_ref
        )

      exp_buf2 = {:buffers, [:b4], 1, 1}
      exp_rest = {:buffers, [:b5, :b6], 2, 2}
      assert result == {:value, [context.buffers1, exp_buf2]}

      list = new_q |> Enum.into([])
      exp_list = Qex.new() |> Qex.push(exp_rest) |> Enum.into([])

      assert list == exp_list
      assert_received Message.new(:demand, _, _)
    end
  end

  test "if the queue works properly for :bytes input metric and :buffers output metric" do
    queue =
      InputQueue.init(%{
        input_demand_unit: :bytes,
        output_demand_unit: :buffers,
        demand_pid: self(),
        demand_pad: :input,
        log_tag: nil,
        toilet?: false,
        target_size: 10,
        min_demand_factor: 1
      })

    assert_receive {Membrane.Core.Message, :demand, 10, [for_pad: :input]}
    assert queue.demand == 0
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    assert queue.size == 4
    queue = InputQueue.store(queue, [%Buffer{payload: "12345678"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    assert queue.size == 16
    assert queue.demand == 0
    {out, queue} = InputQueue.take_and_demand(queue, 2, self(), :input)
    assert bufs_size(out, :buffers) == 2
    assert queue.size == 4
    assert queue.demand == 0
    assert_receive {Membrane.Core.Message, :demand, 12, [for_pad: :input]}
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    {out, queue} = InputQueue.take_and_demand(queue, 1, self(), :input)
    assert bufs_size(out, :buffers) == 1
    assert queue.size == 8
    assert queue.demand == -8
  end

  test "if the queue works properly for :buffers input metric and :bytes output metric" do
    queue =
      InputQueue.init(%{
        input_demand_unit: :buffers,
        output_demand_unit: :bytes,
        demand_pid: self(),
        demand_pad: :input,
        log_tag: nil,
        toilet?: false,
        target_size: 3,
        min_demand_factor: 1
      })

    assert_receive {Membrane.Core.Message, :demand, 3, [for_pad: :input]}
    assert queue.demand == 0
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    assert queue.size == 1
    queue = InputQueue.store(queue, [%Buffer{payload: "12345678"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    assert queue.size == 4
    assert queue.demand == 0
    {out, queue} = InputQueue.take_and_demand(queue, 2, self(), :input)
    assert bufs_size(out, :bytes) == 2
    assert queue.size == 4
    assert queue.demand == 0
    refute_receive {Membrane.Core.Message, :demand, _size, [for_pad: :input]}
    {out, queue} = InputQueue.take_and_demand(queue, 11, self(), :input)
    assert bufs_size(out, :bytes) == 11
    assert queue.size == 2
    assert queue.demand == -1
    assert_receive {Membrane.Core.Message, :demand, 3, [for_pad: :input]}
  end

  defp bufs_size(output, unit) do
    {_state, bufs} = output

    Enum.flat_map(bufs, fn {:buffers, bufs_list, _input_metric_size, _output_metric_size} ->
      bufs_list
    end)
    |> Membrane.Buffer.Metric.from_unit(unit).buffers_size()
  end

  defp bufs(n), do: Enum.to_list(1..n)
end
