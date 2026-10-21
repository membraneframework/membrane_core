defmodule Membrane.Integration.ToiletForwardingTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  @payload_size 8

  defmodule StreamFormat do
    defstruct []
  end

  defmodule AutoFilter do
    use Membrane.Filter, flow_control_hints?: false

    def_input_pad :input, availability: :on_request, accepted_format: _any, flow_control: :auto
    def_output_pad :output, availability: :on_request, accepted_format: _any, flow_control: :auto

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      {[broadcast: buffer], state}
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

  defmodule BytesSink do
    use Membrane.Sink

    def_input_pad :input, accepted_format: _any, flow_control: :manual, demand_unit: :bytes

    @impl true
    def handle_playing(_ctx, state), do: {[notify_parent: :playing], state}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[notify_parent: {:buffer, buffer}], state}
    end

    @impl true
    def handle_parent_notification({:make_demand, bytes}, _ctx, state) do
      {[demand: {:input, bytes}], state}
    end
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
      assert_sink_buffer(pipeline, :sink, buffer)
      assert %Membrane.Buffer{payload: <<buff_idx::64>>} = buffer
      assert buff_idx == i
    end

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet with custom capacity overflows exactly when the capacity is exceeded" do
    toilet_capacity = 50
    target_queue_size = 10
    buffers_filling_toilet = target_queue_size + toilet_capacity

    spec = [
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      child(:source, PushSource)
      |> child(AutoFilter)
      |> via_in(:input, toilet_capacity: toilet_capacity, target_queue_size: target_queue_size)
      |> get_child(:sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    forward_buffers(pipeline, 1..40)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 40})
    assert_buffers_received(pipeline, 1..40)

    forward_buffers(pipeline, 41..(40 + buffers_filling_toilet))
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)

    forward_buffers(pipeline, [40 + buffers_filling_toilet + 1])
    assert_pipeline_crash_group_down(pipeline, :sink_group)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "throttling factor delays the toilet overflow until the decrement is flushed" do
    toilet_capacity = 50
    target_queue_size = 10
    throttling_factor = 10
    flushes_before_overflow = div(target_queue_size + toilet_capacity, throttling_factor)
    buffers_before_overflow = (flushes_before_overflow + 1) * throttling_factor - 1

    spec = [
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      child(:source, PushSource)
      |> child(AutoFilter)
      |> via_in(:input,
        toilet_capacity: toilet_capacity,
        target_queue_size: target_queue_size,
        throttling_factor: throttling_factor
      )
      |> get_child(:sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    forward_buffers(pipeline, 1..buffers_before_overflow)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)

    forward_buffers(pipeline, [buffers_before_overflow + 1])
    assert_pipeline_crash_group_down(pipeline, :sink_group)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet overflow kills the receiver of the push link, not the elements downstream" do
    toilet_capacity = 50
    auto_demand_size = 10
    target_queue_size = 10
    overflowing_burst = 10 * toilet_capacity

    spec = [
      {child(:filter, AutoFilter), group: :filter_group, crash_group_mode: :temporary},
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      child(:pull_source, PullSource)
      |> child(AutoFilter)
      |> via_in(Pad.ref(:input, :pull))
      |> get_child(:filter)
      |> via_in(Pad.ref(:input, 1), auto_demand_size: auto_demand_size)
      |> child(AutoFilter)
      |> via_in(:input, target_queue_size: target_queue_size)
      |> get_child(:sink),
      child(:source, PushSource)
      |> child(AutoFilter)
      |> via_in(Pad.ref(:input, :push),
        toilet_capacity: toilet_capacity,
        auto_demand_size: auto_demand_size
      )
      |> get_child(:filter)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    forward_buffers(pipeline, 1..20)
    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 20})
    assert_buffers_received(pipeline, 1..20)
    refute_pipeline_crash_group_down(pipeline, :filter_group, 300)

    sink_pid = Testing.Pipeline.get_child_pid!(pipeline, :sink)

    forward_buffers(pipeline, 21..(20 + overflowing_burst))
    assert_pipeline_crash_group_down(pipeline, :filter_group)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)
    assert Process.alive?(sink_pid)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet never overflows when the sender works in pull mode" do
    spec = [
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      child(:source, PullSource)
      |> via_in(:input, toilet_capacity: 10)
      |> get_child(:sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    forward_buffers(pipeline, 1..1000)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)
    refute_sink_buffer(pipeline, :sink, _, 0)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 1000})
    assert_buffers_received(pipeline, 1..1000)
    assert Process.alive?(Testing.Pipeline.get_child_pid!(pipeline, :sink))

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "demands in uneven chunks pass through alternating auto and manual filters" do
    buffers_count = 2000
    demand_chunks = [1, 7, 100, 3, 500, 1389]

    spec =
      Enum.reduce(1..5, child(:source, %Testing.Source{output: 1..buffers_count}), fn _i, spec ->
        spec
        |> child(AutoFilter)
        |> child(RedemandingFilter)
      end)
      |> child(:sink, %Testing.Sink{autodemand: false})

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_sink_playing(pipeline, :sink)

    Enum.reduce(demand_chunks, 1, fn chunk, first_payload ->
      Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, chunk})
      last_payload = first_payload + chunk - 1

      for i <- first_payload..last_payload do
        assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^i})
      end

      following_payload = last_payload + 1
      refute_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^following_payload}, 100)
      following_payload
    end)

    assert_end_of_stream(pipeline, :sink)
    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet capacity in bytes counts the payload sizes" do
    toilet_capacity = 100
    target_queue_size = 10
    buffers_before_overflow = div(target_queue_size + toilet_capacity, @payload_size)

    spec = [
      {child(:sink, BytesSink), group: :sink_group, crash_group_mode: :temporary},
      child(:source, PushSource)
      |> child(AutoFilter)
      |> via_in(:input, toilet_capacity: toilet_capacity, target_queue_size: target_queue_size)
      |> get_child(:sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    forward_buffers(pipeline, 1..buffers_before_overflow)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)

    forward_buffers(pipeline, [buffers_before_overflow + 1])
    assert_pipeline_crash_group_down(pipeline, :sink_group)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "sink demanding in bytes through auto filters receives exactly the demanded bytes" do
    buffers_count = 10
    <<payload_3_head::binary-size(4), payload_3_tail::binary-size(4)>> = <<3::64>>

    spec =
      child(:source, PullSource)
      |> child(AutoFilter)
      |> child(AutoFilter)
      |> via_in(:input, target_queue_size: 50)
      |> child(:sink, BytesSink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    assert_pipeline_notified(pipeline, :sink, :playing)

    forward_buffers(pipeline, 1..buffers_count)
    refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)

    [
      {20, [<<1::64>>, <<2::64>>, payload_3_head]},
      {60, [payload_3_tail | Enum.map(4..buffers_count, &<<&1::64>>)]}
    ]
    |> Enum.each(fn {demand_bytes, expected_payloads} ->
      Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, demand_bytes})

      Enum.each(expected_payloads, fn payload ->
        assert_pipeline_notified(pipeline, :sink, {:buffer, %Membrane.Buffer{payload: ^payload}})
      end)

      refute_pipeline_notified(pipeline, :sink, {:buffer, _buffer}, 100)
    end)

    Testing.Pipeline.terminate(pipeline)
  end

  defp forward_buffers(pipeline, payloads) do
    buffers = Enum.map(payloads, &%Membrane.Buffer{payload: <<&1::size(8 * @payload_size)>>})
    Testing.Pipeline.notify_child(pipeline, :source, {:forward_buffers, buffers})
  end

  defp assert_buffers_received(pipeline, range) do
    for i <- range do
      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: <<^i::64>>})
    end
  end
end
