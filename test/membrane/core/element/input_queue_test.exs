defmodule Membrane.Core.Element.InputQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Element.{AtomicDemand, InputQueue}
  alias Membrane.Core.Message
  alias Membrane.Core.SubprocessSupervisor
  alias Membrane.Testing.Event

  require Message

  describe ".init/6 should" do
    setup do
      {:ok,
       %{
         log_tag: "test",
         target_queue_size: 100,
         inbound_demand_unit: :bytes,
         outbound_demand_unit: :bytes,
         pad_ref: :output_pad_ref,
         atomic_demand: new_atomic_demand(),
         expected_metric: Buffer.Metric.from_unit(:bytes)
       }}
    end

    test "return InputQueue struct and send demand message", context do
      assert InputQueue.init(%{
               inbound_demand_unit: context.inbound_demand_unit,
               outbound_demand_unit: context.outbound_demand_unit,
               pad_ref: context.pad_ref,
               log_tag: context.log_tag,
               atomic_demand: context.atomic_demand,
               target_size: context.target_queue_size
             })
             |> Map.put(:stalker_metrics, nil) == %InputQueue{
               q: Qex.new(),
               log_tag: context.log_tag,
               target_size: context.target_queue_size,
               atomic_demand: context.atomic_demand,
               inbound_metric: context.expected_metric,
               outbound_metric: context.expected_metric,
               pad_ref: context.pad_ref,
               size: 0,
               demand: context.target_queue_size,
               stalker_metrics: nil
             }

      assert context.target_queue_size == AtomicDemand.get(context.atomic_demand)

      expected_message = Message.new(:atomic_demand_increased, context.pad_ref)
      assert_received ^expected_message
    end
  end

  describe ".empty?/1 should" do
    setup do
      buffer = %Buffer{payload: <<1, 2, 3>>}

      input_queue =
        prepare_input_queue(
          size: 0,
          inbound_metric: Buffer.Metric.Count,
          outbound_metric: Buffer.Metric.Count,
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
      {:ok,
       %{
         demand: 30,
         size: 10,
         q: Qex.new() |> Qex.push({:buffers, [], 3, 3}),
         payload: <<1, 2, 3>>
       }}
    end

    test "updated properly `size` and `demand` when `:metric` is `Buffer.Metric.Count`",
         context do
      input_queue =
        prepare_input_queue(
          size: context.size,
          inbound_metric: Buffer.Metric.Count,
          outbound_metric: Buffer.Metric.Count,
          q: context.q,
          demand: context.demand
        )

      v = [%Buffer{payload: context.payload}]
      updated_input_queue = InputQueue.store(input_queue, :buffers, v)

      assert updated_input_queue.size == context.size + 1
      assert updated_input_queue.demand == context.demand - 1
    end

    test "updated properly `size` and `demand` when `:metric` is `Buffer.Metric.ByteSize`",
         context do
      input_queue =
        prepare_input_queue(
          size: context.size,
          inbound_metric: Buffer.Metric.ByteSize,
          outbound_metric: Buffer.Metric.ByteSize,
          q: context.q,
          demand: context.demand
        )

      v = [%Buffer{payload: context.payload}]
      updated_input_queue = InputQueue.store(input_queue, :buffers, v)

      assert updated_input_queue.size == context.size + byte_size(context.payload)

      assert updated_input_queue.demand ==
               context.demand - byte_size(context.payload)
    end

    test "append buffer to the queue", context do
      input_queue =
        prepare_input_queue(
          size: context.size,
          inbound_metric: Buffer.Metric.ByteSize,
          outbound_metric: Buffer.Metric.ByteSize,
          q: context.q,
          demand: context.demand
        )

      v = [%Buffer{payload: context.payload}]
      %{q: new_q} = InputQueue.store(input_queue, :buffers, v)
      {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
      assert remaining_q == context.q
      assert last_elem == {:buffers, v, 3, 3}
    end

    test "append event to the queue", context do
      input_queue =
        prepare_input_queue(
          size: context.size,
          inbound_metric: Buffer.Metric.ByteSize,
          outbound_metric: Buffer.Metric.ByteSize,
          q: context.q,
          demand: context.demand
        )

      v = %Event{}
      %{q: new_q} = InputQueue.store(input_queue, :event, v)
      {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
      assert remaining_q == context.q
      assert last_elem == {:non_buffer, :event, v}
    end

    test "keep other fields unchanged after storing an event", context do
      input_queue =
        prepare_input_queue(
          size: context.size,
          inbound_metric: Buffer.Metric.ByteSize,
          outbound_metric: Buffer.Metric.ByteSize,
          q: context.q,
          demand: context.demand
        )

      v = %Event{}
      new_input_queue = InputQueue.store(input_queue, :event, v)
      assert %{new_input_queue | q: context.q} == input_queue
    end
  end

  describe ".take/2 should" do
    setup do
      input_queue =
        InputQueue.init(%{
          inbound_demand_unit: :buffers,
          outbound_demand_unit: :buffers,
          pad_ref: :output_pad_ref,
          log_tag: "test",
          atomic_demand: new_atomic_demand(),
          target_size: 40
        })

      assert_received Message.new(:atomic_demand_increased, :output_pad_ref)

      [input_queue: input_queue]
    end

    test "return {:empty, []} when the queue is empty", %{input_queue: input_queue} do
      old_atomic_demand_value = AtomicDemand.get(input_queue.atomic_demand)
      old_demand = input_queue.demand

      assert {{:empty, []}, %InputQueue{size: 0, demand: ^old_demand}} =
               InputQueue.take(input_queue, 1)

      assert old_atomic_demand_value == AtomicDemand.get(input_queue.atomic_demand)
    end

    test "send demands to the pid and updates demand", %{input_queue: input_queue} do
      assert {{:value, [{:buffers, [1], 1, 1}]}, new_input_queue} =
               input_queue
               |> InputQueue.store(bufs(10))
               |> InputQueue.take(1)

      assert new_input_queue.size == 9
      assert new_input_queue.demand >= 31
      assert AtomicDemand.get(new_input_queue.atomic_demand) >= 41
    end
  end

  describe ".take/2 should also" do
    setup do
      size = 6
      buffers1 = {:buffers, [:b1, :b2, :b3], 3, 3}
      buffers2 = {:buffers, [:b4, :b5, :b6], 3, 3}
      q = Qex.new() |> Qex.push(buffers1) |> Qex.push(buffers2)
      atomic_demand = new_atomic_demand()

      :ok = AtomicDemand.increase(atomic_demand, 94)
      assert_received Message.new(:atomic_demand_increased, :output_pad_ref)

      input_queue =
        prepare_input_queue(
          size: size,
          demand: 94,
          target_size: 100,
          inbound_metric: Buffer.Metric.Count,
          outbound_metric: Buffer.Metric.Count,
          q: q,
          pad_ref: :output_pad_ref,
          atomic_demand: atomic_demand
        )

      {:ok, %{input_queue: input_queue, q: q, size: size, buffers1: buffers1, buffers2: buffers2}}
    end

    test "return tuple {:ok, {:empty, buffers}} when there are not enough buffers",
         context do
      {result, _new_input_queue} = InputQueue.take(context.input_queue, 10)
      assert result == {:empty, [context.buffers1, context.buffers2]}
    end

    test "set `size` to 0 when there are not enough buffers", context do
      {_, %{size: new_size}} = InputQueue.take(context.input_queue, 10)

      assert new_size == 0
    end

    test "increase AtomicDemand hen there are not enough buffers", context do
      old_atomic_demand_value = AtomicDemand.get(context.input_queue.atomic_demand)
      old_demand = context.input_queue.demand

      {_output, input_queue} = InputQueue.take(context.input_queue, 10)

      assert old_atomic_demand_value < AtomicDemand.get(input_queue.atomic_demand)
      assert old_demand < input_queue.demand
    end

    test "return `to_take` buffers from the queue when there are enough buffers and buffers don't have to be split",
         context do
      {result, %{q: new_q}} = InputQueue.take(context.input_queue, 3)

      assert result == {:value, [context.buffers1]}

      list = new_q |> Enum.into([])
      exp_list = Qex.new() |> Qex.push(context.buffers2) |> Enum.into([])

      assert list == exp_list
    end

    test "return `to_take` buffers from the queue when there are enough buffers and buffers have to be split",
         context do
      {result, %{q: new_q}} = InputQueue.take(context.input_queue, 4)

      exp_buf2 = {:buffers, [:b4], 1, 1}
      exp_rest = {:buffers, [:b5, :b6], 2, 2}
      assert result == {:value, [context.buffers1, exp_buf2]}

      list = new_q |> Enum.into([])
      exp_list = Qex.new() |> Qex.push(exp_rest) |> Enum.into([])

      assert list == exp_list
    end
  end

  test "if the queue works properly for :bytes input metric and :buffers output metric" do
    atomic_demand = new_atomic_demand()

    queue =
      InputQueue.init(%{
        inbound_demand_unit: :bytes,
        outbound_demand_unit: :buffers,
        atomic_demand: atomic_demand,
        pad_ref: :output_pad_ref,
        log_tag: nil,
        target_size: 10
      })

    assert_receive Message.new(:atomic_demand_increased, :output_pad_ref)
    assert queue.demand == 10
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    assert queue.size == 4
    queue = InputQueue.store(queue, [%Buffer{payload: "12345678"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = Map.update!(queue, :atomic_demand, &AtomicDemand.decrease(&1, 16))
    assert queue.size == 16
    assert queue.demand == -6
    {out, queue} = InputQueue.take(queue, 2)
    assert bufs_size(out, :buffers) == 2
    assert queue.size == 4
    assert queue.demand >= 6
    assert_receive Message.new(:atomic_demand_increased, :output_pad_ref)

    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    {out, queue} = InputQueue.take(queue, 1)
    assert bufs_size(out, :buffers) == 1
    assert queue.size == 8
    assert queue.demand >= 2
  end

  test "if the queue works properly for :buffers input metric and :bytes output metric" do
    atomic_demand = new_atomic_demand()

    queue =
      InputQueue.init(%{
        inbound_demand_unit: :buffers,
        outbound_demand_unit: :bytes,
        atomic_demand: atomic_demand,
        pad_ref: :output_pad_ref,
        log_tag: nil,
        target_size: 3
      })

    assert_receive Message.new(:atomic_demand_increased, :output_pad_ref)
    assert queue.demand == 3
    queue = InputQueue.store(queue, [%Buffer{payload: "1234"}])
    assert queue.size == 1
    queue = InputQueue.store(queue, [%Buffer{payload: "12345678"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = InputQueue.store(queue, [%Buffer{payload: "12"}])
    queue = Map.update!(queue, :atomic_demand, &AtomicDemand.decrease(&1, 4))
    assert queue.size == 4
    assert queue.demand == -1
    {out, queue} = InputQueue.take(queue, 2)
    assert bufs_size(out, :bytes) == 2
    assert queue.size == 4
    assert queue.demand == -1
    refute_receive Message.new(:atomic_demand_increased, :output_pad_ref)
    {out, queue} = InputQueue.take(queue, 11)
    assert bufs_size(out, :bytes) == 11
    assert queue.size == 2
    assert queue.demand == 1
    assert_receive Message.new(:atomic_demand_increased, :output_pad_ref)
  end

  defp prepare_input_queue(fields) do
    struct(InputQueue, [stalker_metrics: %{size: :atomics.new(1, [])}] ++ fields)
  end

  defp new_atomic_demand(),
    do:
      AtomicDemand.new(%{
        receiver_effective_flow_control: :pull,
        receiver_process: self(),
        receiver_demand_unit: :bytes,
        sender_process: self(),
        sender_pad_ref: :output_pad_ref,
        supervisor: SubprocessSupervisor.start_link!()
      })

  defp bufs_size(output, unit) do
    {_state, bufs} = output

    Enum.flat_map(bufs, fn {:buffers, bufs_list, _inbound_metric_size, _outbound_metric_size} ->
      bufs_list
    end)
    |> Membrane.Buffer.Metric.from_unit(unit).buffers_size()
  end

  defp bufs(n), do: Enum.to_list(1..n)
end
