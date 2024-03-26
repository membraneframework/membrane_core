defmodule Membrane.Test.DelayedDemandsLoopTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Debug
  alias Membrane.Testing

  defmodule Source do
    use Membrane.Source

    defmodule StreamFormat do
      defstruct []
    end

    @sleep_time 5

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :manual

    @impl true
    def handle_demand(_pad, _size, :buffers, %{pads: pads}, state) do
      Process.sleep(@sleep_time)

      stream_format_actions =
        Enum.flat_map(pads, fn
          {pad_ref, %{start_of_stream?: false}} -> [stream_format: {pad_ref, %StreamFormat{}}]
          _pad_entry -> []
        end)

      buffer = %Buffer{payload: "a"}

      buffer_and_redemand_actions =
        Map.keys(pads)
        |> Enum.flat_map(&[buffer: {&1, buffer}, redemand: &1])

      {stream_format_actions ++ buffer_and_redemand_actions, state}
    end

    @impl true
    def handle_parent_notification(:request, _ctx, state) do
      {[notify_parent: :response], state}
    end
  end

  describe "delayed demands loop pauses from time to time, when source has" do
    test "1 pad", do: do_test(1)
    test "2 pads", do: do_test(2)
    test "10 pads", do: do_test(10)
  end

  defp do_test(sinks_number) do
    # auto_demand_size is smaller than delayed_demands_loop_counter_limit, to ensure that
    # after a snapshot, the counter is not reset
    auto_demand_size = 15
    requests_number = 20

    spec =
      [child(:source, Source)] ++
        for i <- 1..sinks_number do
          get_child(:source)
          |> via_in(:input, auto_demand_size: auto_demand_size)
          |> child({:sink, i}, Debug.Sink)
        end

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    for i <- 1..sinks_number do
      assert_start_of_stream(pipeline, {:sink, ^i})
    end

    for _i <- 1..requests_number do
      Testing.Pipeline.notify_child(pipeline, :source, :request)
      assert_pipeline_notified(pipeline, :source, :response)
    end

    Testing.Pipeline.terminate(pipeline)
  end

  defmodule VariousFlowFilter do
    use Membrane.Filter

    def_input_pad :manual_input,
      accepted_format: _any,
      flow_control: :manual,
      demand_unit: :buffers

    def_input_pad :auto_input, accepted_format: _any, flow_control: :auto

    def_output_pad :manual_output, accepted_format: _any, flow_control: :manual
    def_output_pad :auto_output, accepted_format: _any, flow_control: :auto

    defmodule StreamFormat do
      defstruct []
    end

    @impl true
    def handle_playing(_ctx, _state) do
      actions =
        [:manual_output, :auto_output]
        |> Enum.map(&{:stream_format, {&1, %StreamFormat{}}})

      {actions, %{}}
    end

    @impl true
    def handle_demand(:manual_output, size, :buffers, _ctx, state) do
      {[demand: {:manual_input, size}], state}
    end

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      # Aim of this Process.sleep is to make VariousFlowFilter working slower than Testing.Sinks
      Process.sleep(1)

      actions =
        [:manual_output, :auto_output]
        |> Enum.map(&{:buffer, {&1, buffer}})

      {actions, state}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state) do
      {[], state}
    end
  end

  test "manual pad doesn't starve auto pad" do
    buffers_per_source = 10_000
    input_demand_size = 100

    manual_source_buffers =
      Stream.repeatedly(fn -> %Buffer{metadata: :manual, payload: <<>>} end)
      |> Stream.take(buffers_per_source)

    auto_source_buffers =
      Stream.repeatedly(fn -> %Buffer{metadata: :auto, payload: <<>>} end)
      |> Stream.take(buffers_per_source)

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: [
          child(:manual_source, %Testing.Source{output: manual_source_buffers})
          |> via_in(:manual_input, target_queue_size: input_demand_size)
          |> child(:filter, VariousFlowFilter)
          |> via_out(:manual_output)
          |> child(:manual_sink, Testing.Sink),
          child(:auto_source, %Testing.Source{output: auto_source_buffers})
          |> via_in(:auto_input, auto_demand_size: input_demand_size)
          |> get_child(:filter)
          |> via_out(:auto_output)
          |> child(:auto_sink, Testing.Sink)
        ]
      )

    stats = %{manual: 0, auto: 0}

    Enum.reduce(1..10_000, stats, fn _i, stats ->
      assert_sink_buffer(pipeline, :auto_sink, buffer)
      stats = Map.update!(stats, buffer.metadata, &(&1 + 1))

      difference_upperbound =
        max(stats.auto, stats.manual)
        |> div(2)
        |> max(5 * input_demand_size)

      assert abs(stats.auto - stats.manual) <= difference_upperbound

      stats
    end)

    Testing.Pipeline.terminate(pipeline)
  end
end
