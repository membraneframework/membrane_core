defmodule Membrane.Integration.DemandsTest do
  use Bunch
  use ExUnit.Case, async: true

  import ExUnit.Assertions
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Support.DemandsTest.Filter
  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline, Sink, Source}

  defp assert_buffers_received(range, pid) do
    Enum.each(range, fn i ->
      assert_sink_buffer(pid, :sink, %Buffer{payload: <<^i::16>> <> <<255>>})
    end)
  end

  defp test_pipeline(pid) do
    demand = 500
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

    0..(demand - 1)
    |> assert_buffers_received(pid)

    pattern = %Buffer{payload: <<demand::16>> <> <<255>>}
    refute_sink_buffer(pid, :sink, ^pattern, 0)
    Pipeline.message_child(pid, :sink, {:make_demand, demand})

    demand..(2 * demand - 1)
    |> assert_buffers_received(pid)
  end

  test "Regular pipeline with proper demands" do
    links =
      child(:source, Source)
      |> child(:filter, Filter)
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: links)
    test_pipeline(pid)
  end

  test "Pipeline with filter underestimating demand" do
    filter_demand_gen = fn _incoming_demand -> 2 end

    links =
      child(:source, Source)
      |> child(:filter, %Filter{demand_generator: filter_demand_gen})
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: links)
    test_pipeline(pid)
  end

  test "Pipeline with source not generating enough buffers" do
    alias Membrane.Buffer

    actions_gen = fn cnt, _size ->
      cnt..(4 + cnt - 1)
      |> Enum.map(fn cnt ->
        buf = %Buffer{payload: <<cnt::16>>}

        {:buffer, {:output, buf}}
      end)
      |> Enum.concat(redemand: :output)
      ~> {&1, cnt + 4}
    end

    spec =
      child(:source, %Source{output: {0, actions_gen}})
      |> child(:filter, Filter)
      |> child(:sink, %Sink{autodemand: false})

    pid = Pipeline.start_link_supervised!(spec: spec)
    test_pipeline(pid)
  end

  test "handle_demand is not called for pad with end of stream" do
    defmodule Source do
      use Membrane.Source

      defmodule StreamFormat do
        defstruct []
      end

      def_output_pad :output, flow_control: :manual, accepted_format: _any

      @impl true
      def handle_init(_ctx, _opts), do: {[], %{eos_sent?: false}}

      @impl true
      def handle_demand(_pad, _size, _unit, _ctx, %{eos_sent?: true}) do
        raise "handle_demand cannot be called after sending end of stream"
      end

      @impl true
      def handle_demand(:output, n, :buffers, _ctx, %{eos_sent?: false} = state) do
        buffers =
          1..(n - 1)//1
          |> Enum.map(fn _i -> %Membrane.Buffer{payload: <<>>} end)

        Process.send_after(self(), :second_left, 1000)

        {[stream_format: {:output, %StreamFormat{}}, buffer: {:output, buffers}], state}
      end

      @impl true
      def handle_info(:second_left, _ctx, %{eos_sent?: false} = state) do
        buffer = %Membrane.Buffer{payload: <<>>}
        state = %{state | eos_sent?: true}

        {[buffer: {:output, buffer}, end_of_stream: :output], state}
      end
    end

    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input, flow_control: :manual, demand_unit: :buffers, accepted_format: _any

      @impl true
      def handle_playing(_ctx, state), do: {[demand: {:input, 1}], state}

      @impl true
      def handle_buffer(:input, _buffer, _ctx, state), do: {[demand: {:input, 1}], state}
    end

    pipeline = Testing.Pipeline.start_link_supervised!(spec: child(Source) |> child(:sink, Sink))

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.terminate(pipeline)
  end
end
