defmodule Membrane.Core.InputBufferSpec do
  alias Membrane.Core.{InputBuffer, Message}
  alias Membrane.Testing.Event
  require Message
  alias Membrane.Buffer
  use ESpec, async: true

  def flush do
    receive do
      _ -> flush()
    after
      10 -> nil
    end
  end

  describe ".new/3" do
    let :name, do: :name
    let :preferred_size, do: 100
    let :warn_size, do: 200
    let :fail_size, do: 400
    let :min_demand, do: 10
    let :toilet, do: false
    let :demand_unit, do: :bytes
    let :expected_metric, do: Buffer.Metric.from_unit(demand_unit())

    let :props,
      do: [
        preferred_size: preferred_size(),
        min_demand: min_demand(),
        warn_size: warn_size(),
        fail_size: fail_size()
      ]

    it "should return InputBuffer struct and send demand message" do
      expect(
        described_module().new(
          name(),
          demand_unit(),
          toilet(),
          props()
        )
      )
      |> to(
        eq(%InputBuffer{
          name: name(),
          demand: preferred_size(),
          preferred_size: preferred_size(),
          min_demand: min_demand(),
          toilet: toilet(),
          metric: expected_metric(),
          q: Qex.new()
        })
      )
    end

    context "if toilet is not false" do
      let :toilet, do: true

      it "should not send the demand" do
        flush()

        expect(
          described_module().new(
            name(),
            demand_unit(),
            toilet(),
            props()
          )
        )
        |> to(
          eq(%InputBuffer{
            name: name(),
            demand: preferred_size(),
            preferred_size: preferred_size(),
            min_demand: min_demand(),
            toilet: %{warn: warn_size(), fail: fail_size()},
            metric: expected_metric(),
            q: Qex.new()
          })
        )
      end
    end
  end

  describe ".empty?/1" do
    let :current_size, do: 0

    let :input_buf,
      do: %InputBuffer{
        current_size: current_size(),
        metric: Buffer.Metric.Count,
        q: Qex.new()
      }

    context "when pull buffer is empty" do
      it "should return true" do
        expect(described_module().empty?(input_buf())) |> to(eq true)
      end
    end

    context "when pull buffer contains some buffers" do
      let :buffer, do: %Buffer{payload: <<1, 2, 3>>}

      let :not_empty_input_buf,
        do: described_module().store(input_buf(), :buffers, [buffer()]) |> elem(1)

      it "should return false" do
        expect(described_module().empty?(not_empty_input_buf())) |> to(eq false)
      end
    end
  end

  describe ".store/3" do
    let :current_size, do: 10
    let :q, do: Qex.new() |> Qex.push({:buffers, [], 3})
    let :metric, do: Buffer.Metric.Count

    let :input_buf,
      do: %InputBuffer{
        current_size: current_size(),
        metric: metric(),
        q: q()
      }

    context "when `type` is :buffers" do
      let :type, do: :buffers
      let :payload, do: <<1, 2, 3>>
      let :v, do: [%Buffer{payload: payload()}]

      context "when metric is `Count`" do
        it "should increment `current_size`" do
          {:ok, %{current_size: new_current_size}} =
            described_module().store(input_buf(), type(), v())

          expect(new_current_size) |> to(eq(current_size() + 1))
        end
      end

      context "when metric is `ByteSize`" do
        let :metric, do: Buffer.Metric.ByteSize

        it "should add payload size to `current_size`" do
          {:ok, %{current_size: new_current_size}} =
            described_module().store(input_buf(), type(), v())

          expect(new_current_size) |> to(eq(current_size() + byte_size(payload())))
        end
      end

      it "should append buffer to the queue" do
        {:ok, %{q: new_q}} = described_module().store(input_buf(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:buffers, v(), 1})
      end
    end

    context "when `type` is :event" do
      let :type, do: :event
      let :v, do: %Event{}

      it "should append event to the queue" do
        {:ok, %{q: new_q}} = described_module().store(input_buf(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:non_buffer, :event, v()})
      end

      it "should keep other fields unchanged" do
        {:ok, new_input_buf} = described_module().store(input_buf(), type(), v())
        expect(%{new_input_buf | q: q()}) |> to(eq input_buf())
      end
    end
  end

  describe ".take/2" do
    let :buffers1, do: {:buffers, [:b1, :b2, :b3], 3}
    let :buffers2, do: {:buffers, [:b4, :b5, :b6], 3}
    let :q, do: Qex.new() |> Qex.push(buffers1()) |> Qex.push(buffers2())
    let :current_size, do: 6
    let :linked_output_ref, do: :linked_output_ref
    let :metric, do: Buffer.Metric.Count

    let :input_buf,
      do: %InputBuffer{
        current_size: current_size(),
        demand: 0,
        min_demand: 0,
        metric: metric(),
        q: q()
      }

    context "when there are not enough buffers" do
      let :to_take, do: 10

      it "should return tuple {:ok, {:empty, buffers}}" do
        {result, _new_input_buf} = described_module().take(input_buf(), to_take())
        expect(result) |> to(eq {:ok, {:empty, [buffers1(), buffers2()]}})
      end

      it "should set `current_size` to 0" do
        {_, %{current_size: new_size}} = described_module().take(input_buf(), to_take())
        expect(new_size) |> to(eq 0)
      end
    end

    context "when there are enough buffers" do
      context "and buffers dont have to be splitted" do
        let :to_take, do: 3

        it "should return `to_take` buffers from the queue" do
          {{:ok, result}, %{q: new_q}} = described_module().take(input_buf(), to_take())
          expect(result) |> to(eq {:value, [buffers1()]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new() |> Qex.push(buffers2()) |> Enum.into([])

          expect(list) |> to(eq exp_list)
        end
      end

      context "and buffers have to be splitted" do
        let :to_take, do: 4

        it "should return `to_take` buffers from the queue" do
          {{:ok, result}, %{q: new_q}} = described_module().take(input_buf(), to_take())
          exp_buf2 = {:buffers, [:b4], 1}
          exp_rest = {:buffers, [:b5, :b6], 2}
          expect(result) |> to(eq {:value, [buffers1(), exp_buf2]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new() |> Qex.push(exp_rest) |> Enum.into([])

          expect(list) |> to(eq exp_list)
        end
      end
    end
  end
end
