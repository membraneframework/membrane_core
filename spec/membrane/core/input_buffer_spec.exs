defmodule Membrane.Core.Element.InputQueueSpec do
  use ESpec, async: true

  alias Membrane.Buffer
  alias Membrane.Core.Message
  alias Membrane.Core.Element.InputQueue
  alias Membrane.Testing.Event

  require Message

  def flush do
    receive do
      _ -> flush()
    after
      10 -> nil
    end
  end

  describe ".init/6" do
    let :log_tag, do: "test"
    let :target_queue_size, do: 100
    let :min_demand_factor, do: 0.1
    let :demand_unit, do: :bytes
    let :demand_pid, do: self()
    let :linked_output_ref, do: :output_pad_ref
    let :toilet?, do: false
    let :expected_metric, do: Buffer.Metric.from_unit(demand_unit())
    let :expected_min_demand, do: 10

    it "should return InputQueue struct and send demand message" do
      expect(
        described_module().init(%{
          demand_unit: demand_unit(),
          demand_pid: demand_pid(),
          demand_pad: linked_output_ref(),
          log_tag: log_tag(),
          toilet?: toilet?(),
          target_size: target_queue_size(),
          min_demand_factor: min_demand_factor()
        })
      )
      |> to(
        eq(%InputQueue{
          q: Qex.new(),
          log_tag: log_tag(),
          target_size: target_queue_size(),
          size: 0,
          demand: 0,
          min_demand: expected_min_demand(),
          metric: expected_metric(),
          toilet?: toilet?()
        })
      )

      message = Message.new(:demand, target_queue_size(), for_pad: linked_output_ref())
      assert_received ^message
    end

    context "if toilet is enabled" do
      let :toilet?, do: true

      it "should not send the demand" do
        flush()

        expect(
          described_module().init(%{
            demand_unit: demand_unit(),
            demand_pid: demand_pid(),
            demand_pad: linked_output_ref(),
            log_tag: log_tag(),
            toilet?: toilet?(),
            target_size: target_queue_size(),
            min_demand_factor: min_demand_factor()
          })
        )
        |> to(
          eq(%InputQueue{
            q: Qex.new(),
            log_tag: log_tag(),
            target_size: target_queue_size(),
            size: 0,
            demand: target_queue_size(),
            min_demand: expected_min_demand(),
            metric: expected_metric(),
            toilet?: toilet?()
          })
        )

        refute_received Message.new(:demand, _)
      end
    end
  end

  describe ".empty?/1" do
    let :size, do: 0

    let :input_queue,
      do:
        struct(InputQueue,
          size: size(),
          metric: Buffer.Metric.Count,
          q: Qex.new()
        )

    context "when pull buffer is empty" do
      it "should return true" do
        expect(described_module().empty?(input_queue())) |> to(eq true)
      end
    end

    context "when pull buffer contains some buffers" do
      let :buffer, do: %Buffer{payload: <<1, 2, 3>>}

      let :not_empty_input_queue,
        do: described_module().store(input_queue(), :buffers, [buffer()])

      it "should return false" do
        expect(described_module().empty?(not_empty_input_queue())) |> to(eq false)
      end
    end
  end

  describe ".store/3" do
    let :size, do: 10
    let :q, do: Qex.new() |> Qex.push({:buffers, [], 3})
    let :metric, do: Buffer.Metric.Count

    let :input_queue,
      do:
        struct(InputQueue,
          size: size(),
          metric: metric(),
          q: q()
        )

    context "when `type` is :buffers" do
      let :type, do: :buffers
      let :payload, do: <<1, 2, 3>>
      let :v, do: [%Buffer{payload: payload()}]

      context "when metric is `Count`" do
        it "should increment `size`" do
          %{size: new_size} = described_module().store(input_queue(), type(), v())

          expect(new_size) |> to(eq(size() + 1))
        end
      end

      context "when metric is `ByteSize`" do
        let :metric, do: Buffer.Metric.ByteSize

        it "should add payload size to `size`" do
          %{size: new_size} = described_module().store(input_queue(), type(), v())

          expect(new_size) |> to(eq(size() + byte_size(payload())))
        end
      end

      it "should append buffer to the queue" do
        %{q: new_q} = described_module().store(input_queue(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:buffers, v(), 1})
      end
    end

    context "when `type` is :event" do
      let :type, do: :event
      let :v, do: %Event{}

      it "should append event to the queue" do
        %{q: new_q} = described_module().store(input_queue(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:non_buffer, :event, v()})
      end

      it "should keep other fields unchanged" do
        new_input_queue = described_module().store(input_queue(), type(), v())
        expect(%{new_input_queue | q: q()}) |> to(eq input_queue())
      end
    end
  end

  describe ".take_and_demand/4" do
    let :buffers1, do: {:buffers, [:b1, :b2, :b3], 3}
    let :buffers2, do: {:buffers, [:b4, :b5, :b6], 3}
    let :q, do: Qex.new() |> Qex.push(buffers1()) |> Qex.push(buffers2())
    let :size, do: 6
    let :demand_pid, do: self()
    let :linked_output_ref, do: :linked_output_ref
    let :metric, do: Buffer.Metric.Count

    let :input_queue,
      do:
        struct(InputQueue,
          size: size(),
          demand: 0,
          min_demand: 0,
          target_queue_size: 100,
          toilet?: false,
          metric: metric(),
          q: q()
        )

    context "when there are not enough buffers" do
      let :to_take, do: 10

      it "should return tuple {:ok, {:empty, buffers}}" do
        {result, _new_input_queue} =
          described_module().take_and_demand(
            input_queue(),
            to_take(),
            demand_pid(),
            linked_output_ref()
          )

        expect(result) |> to(eq {:empty, [buffers1(), buffers2()]})
      end

      it "should set `size` to 0" do
        {_, %{size: new_size}} =
          described_module().take_and_demand(
            input_queue(),
            to_take(),
            demand_pid(),
            linked_output_ref()
          )

        expect(new_size) |> to(eq 0)
      end

      it "should generate demand" do
        described_module().take_and_demand(
          input_queue(),
          to_take(),
          demand_pid(),
          linked_output_ref()
        )

        expected_size = size()
        pad_ref = linked_output_ref()
        message = Message.new(:demand, expected_size, for_pad: pad_ref)
        assert_received ^message
      end
    end

    context "when there are enough buffers" do
      context "and buffers dont have to be split" do
        let :to_take, do: 3

        it "should return `to_take` buffers from the queue" do
          {result, %{q: new_q}} =
            described_module().take_and_demand(
              input_queue(),
              to_take(),
              demand_pid(),
              linked_output_ref()
            )

          expect(result) |> to(eq {:value, [buffers1()]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new() |> Qex.push(buffers2()) |> Enum.into([])

          expect(list) |> to(eq exp_list)
          assert_received Message.new(:demand, _, _)
        end
      end

      context "and buffers have to be split" do
        let :to_take, do: 4

        it "should return `to_take` buffers from the queue" do
          {result, %{q: new_q}} =
            described_module().take_and_demand(
              input_queue(),
              to_take(),
              demand_pid(),
              linked_output_ref()
            )

          exp_buf2 = {:buffers, [:b4], 1}
          exp_rest = {:buffers, [:b5, :b6], 2}
          expect(result) |> to(eq {:value, [buffers1(), exp_buf2]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new() |> Qex.push(exp_rest) |> Enum.into([])

          expect(list) |> to(eq exp_list)
          assert_received Message.new(:demand, _, _)
        end
      end
    end
  end
end
