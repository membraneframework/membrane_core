defmodule Membrane.Integration.ToiletForwardingTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule StreamFormat do
    defstruct []
  end

  defmodule AutoFilter do
    use Membrane.Filter

    def_input_pad :input, availability: :on_request, accepted_format: _any, flow_control: :auto
    def_output_pad :output, availability: :on_request, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      {[forward: buffer], state}
    end

    @impl true
    def handle_parent_notification({:execute_actions, actions}, _ctx, state) do
      {actions, state}
    end
  end

  defmodule PushSink do
    use Membrane.Sink
    def_input_pad :input, accepted_format: _any, flow_control: :push
  end

  defmodule AutoSink do
    use Membrane.Sink
    def_input_pad :input, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_parent_notification({:sleep, timeout}, _cts, state) do
      Process.sleep(timeout)
      {[], state}
    end

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      {[notify_parent: {:buffer, buffer}], state}
    end
  end

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :push

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}], state}
    end

    @impl true
    def handle_parent_notification({:forward_buffers, buffers}, _ctx, state) do
      {[buffer: {:output, buffers}], state}
    end
  end

  defmodule PullSource do
    use Membrane.Source

    defmodule StreamFormat do
      defstruct []
    end

    def_output_pad :output, accepted_format: _any, flow_control: :manual

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}], state}
    end

    @impl true
    def handle_parent_notification({:forward_buffers, buffers}, _ctx, state) do
      {[buffer: {:output, buffers}], state}
    end

    @impl true
    def handle_demand(_pad, _demand, _unit, _ctx, state), do: {[], state}
  end

  defmodule RedemandingFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, flow_control: :manual, demand_unit: :buffers
    def_output_pad :output, accepted_format: _any, flow_control: :manual, demand_unit: :buffers

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, state) do
      {[demand: :input], state}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[buffer: {:output, buffer}, redemand: :output], state}
    end
  end

  test "toilet overflows only where it should" do
    # because Membrane.Testing.Source output pad has :manual flow control, :filter will work in auto pull

    spec = [
      {child(:filter, AutoFilter), group: :filter_group, crash_group_mode: :temporary},
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      child(Testing.Source)
      |> child(AutoFilter)
      |> get_child(:filter)
      |> get_child(:sink),
      child(:push_source, PushSource)
      |> child(AutoFilter)
      |> get_child(:filter)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(500)

    buffers =
      1..10_000
      |> Enum.map(fn i -> %Membrane.Buffer{payload: <<i::64>>} end)

    Testing.Pipeline.execute_actions(pipeline,
      notify_child: {:push_source, {:forward_buffers, buffers}}
    )

    assert_pipeline_crash_group_down(pipeline, :filter_group)

    Testing.Pipeline.terminate(pipeline)
  end

  test "toilet does not overflow on link between 2 pads in auto push" do
    spec =
      child(:source, PushSource)
      |> child(AutoFilter)
      |> child(:sink, AutoSink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Testing.Pipeline.execute_actions(pipeline, notify_child: {:sink, {:sleep, 1000}})
    Process.sleep(100)

    buffers =
      1..10_000
      |> Enum.map(fn i -> %Membrane.Buffer{payload: <<i::64>>} end)

    Testing.Pipeline.execute_actions(pipeline,
      notify_child: {:source, {:forward_buffers, buffers}}
    )

    refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 500)

    for i <- 1..10_000 do
      assert_pipeline_notified(
        pipeline,
        :sink,
        {:buffer, %Membrane.Buffer{payload: <<buff_idx::64>>}}
      )

      assert buff_idx == i
    end

    Testing.Pipeline.terminate(pipeline)
  end

  test "toilet does not overflow on link between 2 pads in auto pull" do
    spec =
      child(PullSource)
      |> child(:filter, AutoFilter)
      |> via_out(Pad.ref(:output, 1))
      |> child(:sink, AutoSink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    # time to propagate :pull effective flow control
    Process.sleep(100)

    buffers =
      1..10_000
      |> Enum.map(fn i -> %Membrane.Buffer{payload: <<i::64>>} end)

    filter_actions = [
      stream_format: {Pad.ref(:output, 1), %StreamFormat{}},
      buffer: {Pad.ref(:output, 1), buffers}
    ]

    Testing.Pipeline.execute_actions(pipeline,
      notify_child: {:filter, {:execute_actions, filter_actions}}
    )

    for i <- 1..10_000 do
      assert_pipeline_notified(
        pipeline,
        :sink,
        {:buffer, %Membrane.Buffer{payload: <<buff_idx::64>>}}
      )

      assert buff_idx == i
    end

    Testing.Pipeline.terminate(pipeline)
  end

  test "elements in auto pull work properly with elements in manual pull" do
    spec =
      Enum.reduce(1..20, child(:source, PullSource), fn _i, spec ->
        spec
        |> child(AutoFilter)
        |> child(RedemandingFilter)
      end)
      |> child(:sink, %Testing.Sink{autodemand: false})

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_playing(pipeline, :sink)

    buffers =
      1..4000
      |> Enum.map(fn i -> %Membrane.Buffer{payload: <<i::64>>} end)

    Testing.Pipeline.execute_actions(pipeline,
      notify_child: {:source, {:forward_buffers, buffers}},
      notify_child: {:sink, {:make_demand, 3000}}
    )

    for i <- 1..3000 do
      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: <<buff_idx::64>>})
      assert buff_idx == i
    end

    Testing.Pipeline.terminate(pipeline)
  end
end
