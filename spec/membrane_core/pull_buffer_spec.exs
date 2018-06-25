defmodule Membrane.PullBufferSpec do
  use ESpec, async: false

  describe ".new/5" do
    let :name, do: :name
    let :sink, do: :sink
    let :sink_name, do: :sink_name
    let :preferred_size, do: 100
    let :min_demand, do: 10
    let :toilet, do: false
    let :demand_in, do: :bytes
    let :expected_metric, do: Membrane.Buffer.Metric.from_unit(demand_in())

    let :props,
      do: [
        preferred_size: preferred_size(),
        min_demand: min_demand(),
        toilet: toilet()
      ]

    it "should return PullBuffer struct" do
      expect(described_module().new(name(), sink(), sink_name(), demand_in(), props()))
      |> to(
        eq(%Membrane.PullBuffer{
          name: name(),
          sink: sink(),
          sink_name: sink_name(),
          demand: preferred_size(),
          preferred_size: preferred_size(),
          min_demand: min_demand(),
          toilet: toilet(),
          metric: expected_metric(),
          q: Qex.new()
        })
      )
    end
  end

  describe ".fill/1" do
    let :toilet, do: false
    let :demand, do: 10
    let :pref_size, do: 50
    let :sink_pid, do: self()
    let :sink_name, do: :name
    let :sink, do: {sink_pid(), sink_name()}
    let :current_size, do: 0

    let :pb,
      do: %Membrane.PullBuffer{
        toilet: toilet(),
        preferred_size: pref_size(),
        sink: {sink_pid(), sink_name()},
        demand: demand(),
        min_demand: 10,
        current_size: current_size()
      }

    context "when toilet is not false" do
      let :toilet, do: true

      it "should do nothing" do
        expect(described_module().fill(pb())) |> to(eq {:ok, pb()})
        refute_received {:membrane_demand, _}
      end
    end

    context "when pullbuffer is full" do
      let :current_size, do: pref_size()

      it "should do nothing" do
        described_module().fill(pb())
        refute_received {:membrane_demand, _}
      end
    end

    xcontext "when pullbuffer isn't full, but contains some elements" do
    end

    context "when pullbuffer is empty" do
      let :demand, do: pref_size()
      let :current_size, do: 0

      it "should send :membrane_demand message and update `demand`" do
        {:ok, new_pb} = described_module().fill(pb())
        expect(new_pb.demand) |> to(eq 0)
        expected_list = [demand(), sink_name()]

        assert_received {:membrane_demand, ^expected_list}
      end
    end
  end

  describe ".empty?/1" do
    let :current_size, do: 0

    let :pb,
      do: %Membrane.PullBuffer{
        current_size: current_size(),
        metric: Membrane.Buffer.Metric.Count,
        q: Qex.new()
      }

    context "when pull buffer is empty" do
      it "should return true" do
        expect(described_module().empty?(pb())) |> to(eq true)
      end
    end

    context "when pull buffer contains some buffers" do
      let :buffer, do: %Membrane.Buffer{payload: <<1, 2, 3>>}
      let :not_empty_pb, do: described_module().store(pb(), :buffers, [buffer()]) |> elem(1)

      it "should return false" do
        expect(described_module().empty?(not_empty_pb())) |> to(eq false)
      end
    end
  end

  describe ".store/3" do
    let :current_size, do: 10
    let :q, do: Qex.new() |> Qex.push({:buffers, [], 3})
    let :metric, do: Membrane.Buffer.Metric.Count

    let :pb,
      do: %Membrane.PullBuffer{
        current_size: current_size(),
        metric: metric(),
        q: q()
      }

    context "when `type` is :buffers" do
      let :type, do: :buffers
      let :payload, do: <<1, 2, 3>>
      let :v, do: [%Membrane.Buffer{payload: payload()}]

      context "when metric is `Count`" do
        it "should increment `current_size`" do
          {:ok, %{current_size: new_current_size}} = described_module().store(pb(), type(), v())
          expect(new_current_size) |> to(eq(current_size() + 1))
        end
      end

      context "when metric is `ByteSize`" do
        let :metric, do: Membrane.Buffer.Metric.ByteSize

        it "should add payload size to `current_size`" do
          {:ok, %{current_size: new_current_size}} = described_module().store(pb(), type(), v())
          expect(new_current_size) |> to(eq(current_size() + byte_size(payload())))
        end
      end

      it "should append buffer to the queue" do
        {:ok, %{q: new_q}} = described_module().store(pb(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:buffers, v(), 1})
      end
    end

    context "when `type` is :event" do
      let :type, do: :event
      let :v, do: %Membrane.Event{type: :some_type, payload: :some_payload}

      it "should append event to the queue" do
        {:ok, %{q: new_q}} = described_module().store(pb(), type(), v())
        {{:value, last_elem}, remaining_q} = new_q |> Qex.pop_back()
        expect(remaining_q) |> to(eq q())
        expect(last_elem) |> to(eq {:non_buffer, :event, v()})
      end

      it "should keep other fields unchanged" do
        {:ok, new_pb} = described_module().store(pb(), type(), v())
        expect(%{new_pb | q: q()}) |> to(eq pb())
      end
    end
  end

  describe ".take/2" do
    let :buffers1, do: {:buffers, [:b1, :b2, :b3], 3}
    let :buffers2, do: {:buffers, [:b4, :b5, :b6], 3}
    let :q, do: Qex.new() |> Qex.push(buffers1()) |> Qex.push(buffers2())
    let :current_size, do: 6
    let :sink_name, do: :sink_name
    let :metric, do: Membrane.Buffer.Metric.Count

    let :pb,
      do: %Membrane.PullBuffer{
        current_size: current_size(),
        demand: 0,
        min_demand: 0,
        sink: {self(), sink_name()},
        metric: metric(),
        q: q()
      }

    context "when there are not enough buffers" do
      let :to_take, do: 10
      #it "should return tuple {:ok, {:empty, buffers}}" do
      #  {result, _new_pb} = described_module().take(pb(), to_take())
      #  expect(result) |> to(eq {:ok, {:empty, [buffers1(), buffers2()]}})
      #end

      #it "should set `current_size` to 0" do
      #  {_, %{current_size: new_size}} = described_module().take(pb(), to_take())
      #  expect(new_size) |> to(eq 0)
      #end

      it "should generate demand" do
        described_module().take(pb(), to_take())
        expected_list = [current_size(), sink_name()]

        assert_received {:membrane_demand, ^expected_list}
      end
    end

    context "when there are enough buffers" do
      context "and buffers dont have to be splitted" do
        let :to_take, do: 3

        it "should return `to_take` buffers from the queue" do
          {{:ok, result}, %{q: new_q}} = described_module().take(pb(), to_take())
          expect(result) |> to(eq {:value, [buffers1()]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new |> Qex.push(buffers2()) |> Enum.into([])

          expect(list) |> to(eq exp_list)
          assert_received {:membrane_demand, _}
        end
      end

      context "and buffers have to be splitted" do
        let :to_take, do: 4

        it "should return `to_take` buffers from the queue" do
          {{:ok, result}, %{q: new_q}} = described_module().take(pb(), to_take())
          exp_buf2 = {:buffers, [:b4], 1}
          exp_rest = {:buffers, [:b5, :b6], 2}
          expect(result) |> to(eq {:value, [buffers1(), exp_buf2]})

          list = new_q |> Enum.into([])
          exp_list = Qex.new |> Qex.push(exp_rest) |> Enum.into([])

          expect(list) |> to(eq exp_list)
          assert_received {:membrane_demand, _}
        end
      end
      
    end
  end
end

