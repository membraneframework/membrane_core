defmodule Membrane.Integration.EffectiveFlowControlResolutionTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.DemandsTest.ControlledSource
  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule AutoFilter do
    use Membrane.Filter, flow_control_hints?: false

    def_input_pad :input, availability: :on_request, accepted_format: _any
    def_output_pad :output, availability: :on_request, accepted_format: _any

    def_options lazy?: [spec: boolean(), default: false]

    @impl true
    def handle_playing(_ctx, state) do
      {[notify_parent: :playing], state}
    end

    @impl true
    def handle_buffer(_pad, buffer, _ctx, state) do
      if state.lazy?, do: Process.sleep(100)
      {[broadcast: buffer], state}
    end

    @impl true
    def handle_end_of_stream(_pad, _ctx, state) do
      {[], state}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      {[notify_parent: {:pad_removed, pad}], state}
    end
  end

  defmodule DoubleFlowControlSource do
    use Membrane.Source

    def_output_pad :push_output, accepted_format: _any, flow_control: :push
    def_output_pad :pull_output, accepted_format: _any, flow_control: :manual

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state), do: {[], state}
  end

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :push

    @impl true
    def handle_playing(_ctx, state) do
      actions = [stream_format: {:output, %Membrane.StreamFormat.Mock{}}, notify_parent: :playing]
      {actions, state}
    end

    @impl true
    def handle_parent_notification(actions, _ctx, state), do: {actions, state}
  end

  defmodule PullSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :manual

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state), do: {[], state}
  end

  defmodule BatchingSource do
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :push

    @impl true
    def handle_playing(_ctx, state) do
      # buffers_barch is bigger than sum of default toilet capacity and default initial auto demand
      buffers_batch = Enum.map(1..5_000, &%Membrane.Buffer{payload: inspect(&1)})

      actions = [
        stream_format: {:output, %Membrane.StreamFormat.Mock{}},
        buffer: {:output, buffers_batch}
      ]

      {actions, state}
    end
  end

  test "effective_flow_control is properly resolved in simple scenario" do
    spec_beggining = [
      child({:filter_a, 0}, AutoFilter),
      child({:filter_b, 0}, AutoFilter)
    ]

    spec =
      Enum.reduce(1..10, spec_beggining, fn idx, [predecessor_a, predecessor_b] ->
        [
          predecessor_a
          |> child({:filter_a, idx}, AutoFilter),
          predecessor_b
          |> child({:filter_b, idx}, AutoFilter)
        ]
      end)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    children_names =
      for filter_type <- [:filter_a, :filter_b], idx <- 0..10 do
        {filter_type, idx}
      end

    children_names
    |> Enum.map(fn child ->
      assert_pipeline_notified(pipeline, child, :playing)
      child
    end)
    |> Enum.each(fn child ->
      assert_child_effective_flow_control(pipeline, child, :push)
    end)

    Testing.Pipeline.execute_actions(pipeline,
      spec: [
        child(:source, DoubleFlowControlSource)
        |> via_out(:push_output)
        |> get_child({:filter_a, 0}),
        get_child(:source) |> via_out(:pull_output) |> get_child({:filter_b, 0})
      ]
    )

    Process.sleep(1000)

    for child <- children_names do
      expected =
        case child do
          {:filter_a, _idx} -> :push
          {:filter_b, _idx} -> :pull
        end

      assert_child_effective_flow_control(pipeline, child, expected)
    end
  end

  test "effective_flow_control is :pull, only when it should be" do
    spec = [
      child(:push_source, PushSource)
      |> child(:filter_1, AutoFilter)
      |> child(:filter_2, AutoFilter),
      child(:pull_source, PullSource)
      |> get_child(:filter_2)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(500)

    assert_child_effective_flow_control(pipeline, :filter_1, :push)
    assert_child_effective_flow_control(pipeline, :filter_2, :pull)
  end

  test "Toilet does not overflow, when input pad effective flow control is :push" do
    spec =
      child(:source, BatchingSource)
      |> child(:filter, AutoFilter)

    pipeline = Testing.Pipeline.start_supervised!(spec: spec)
    Process.sleep(500)

    child_pid = Testing.Pipeline.get_child_pid!(pipeline, :filter)
    assert Process.alive?(child_pid)

    Testing.Pipeline.terminate(pipeline)
  end

  test "Toilet overflows, when it should" do
    spec = {
      child(:pull_source, PullSource)
      |> child(:filter, %AutoFilter{lazy?: true}),
      group: :group, crash_group_mode: :temporary
    }

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)
    Process.sleep(500)

    assert_child_effective_flow_control(pipeline, :filter, :pull)

    monitor_ref =
      Testing.Pipeline.get_child_pid!(pipeline, :filter)
      |> Process.monitor()

    Testing.Pipeline.execute_actions(pipeline,
      spec: {
        child(:batching_source, BatchingSource)
        |> get_child(:filter),
        group: :another_group, crash_group_mode: :temporary
      }
    )

    # batch of buffers sent by BatchingSource should cause toilet overflow
    assert_receive {:DOWN, ^monitor_ref, _process, _pid, :killed}
    assert_pipeline_crash_group_down(pipeline, :group)
    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "toilet moves to the auto filter input when its effective flow control switches to :pull" do
    buffers_within_toilet_capacity = 150
    buffers_above_toilet_capacity = 1000

    spec = [
      {child(:push_source, PushSource) |> child(:filter_1, AutoFilter),
       group: :upstream_group, crash_group_mode: :temporary},
      {child(:sink, %Testing.Sink{autodemand: false}),
       group: :sink_group, crash_group_mode: :temporary},
      get_child(:filter_1) |> child(:filter_2, AutoFilter) |> get_child(:sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_pipeline_notified(pipeline, :push_source, :playing)
    assert_sink_playing(pipeline, :sink)

    send_buffers(pipeline, :push_source, 1..buffers_within_toilet_capacity)
    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, buffers_within_toilet_capacity})
    assert_sink_payloads(pipeline, 1..buffers_within_toilet_capacity)

    filter_1_monitor =
      Testing.Pipeline.get_child_pid!(pipeline, :filter_1)
      |> Process.monitor()

    Testing.Pipeline.execute_actions(pipeline,
      spec: {
        child(:pull_source, ControlledSource)
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:filter_1),
        group: :upstream_group, crash_group_mode: :temporary
      }
    )

    assert_pipeline_notified(pipeline, :pull_source, :playing)
    assert_child_effective_flow_control(pipeline, :filter_1, :pull)

    first_payload_above_capacity = buffers_within_toilet_capacity + 1

    send_buffers(
      pipeline,
      :push_source,
      first_payload_above_capacity..(buffers_within_toilet_capacity +
                                       buffers_above_toilet_capacity)
    )

    assert_receive {:DOWN, ^filter_1_monitor, :process, _pid, :killed}
    assert_pipeline_crash_group_down(pipeline, :upstream_group)
    refute_pipeline_crash_group_down(pipeline, :sink_group, 300)
    assert Testing.Pipeline.get_child_pid!(pipeline, :sink) |> Process.alive?()
    assert Testing.Pipeline.get_child_pid!(pipeline, :filter_2) |> Process.alive?()

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "effective_flow_control follows the linked pull inputs and buffers keep flowing" do
    push_batch_above_toilet_capacity = 1000

    spec =
      child(:push_source, PushSource)
      |> child(:filter_1, AutoFilter)
      |> child(:filter_2, AutoFilter)
      |> via_in(:input, toilet_capacity: 2 * push_batch_above_toilet_capacity)
      |> child(:sink, Testing.Sink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_pipeline_notified(pipeline, :push_source, :playing)
    assert_pipeline_notified(pipeline, :filter_1, :playing)
    assert_pipeline_notified(pipeline, :filter_2, :playing)

    next_payload =
      Enum.reduce(1..2, 1, fn i, next_payload ->
        Testing.Pipeline.execute_actions(pipeline,
          spec: child({:pull_source, i}, ControlledSource) |> get_child(:filter_1)
        )

        assert_pipeline_notified(pipeline, {:pull_source, i}, :playing)
        assert_child_effective_flow_control(pipeline, :filter_1, :pull)
        last_payload = next_payload + 99
        send_buffers(pipeline, :push_source, next_payload..last_payload)
        assert_sink_payloads(pipeline, next_payload..last_payload)
        assert_child_effective_flow_control(pipeline, :filter_2, :pull)

        Testing.Pipeline.execute_actions(pipeline, remove_children: {:pull_source, i})
        assert_pipeline_notified(pipeline, :filter_1, {:pad_removed, Pad.ref(:input, _ref)})
        assert_child_effective_flow_control(pipeline, :filter_1, :push)
        next_payload = last_payload + 1
        last_payload = next_payload + push_batch_above_toilet_capacity - 1
        send_buffers(pipeline, :push_source, next_payload..last_payload)
        assert_sink_payloads(pipeline, next_payload..last_payload)
        assert_child_effective_flow_control(pipeline, :filter_2, :push)
        last_payload + 1
      end)

    Testing.Pipeline.execute_actions(pipeline,
      spec: child(:pull_source, ControlledSource) |> get_child(:filter_1)
    )

    assert_pipeline_notified(pipeline, :pull_source, :playing)
    Testing.Pipeline.execute_actions(pipeline, remove_children: :push_source)
    assert_pipeline_notified(pipeline, :filter_1, {:pad_removed, Pad.ref(:input, _ref)})
    assert_child_effective_flow_control(pipeline, :filter_1, :pull)
    send_buffers(pipeline, :pull_source, next_payload..(next_payload + 99))
    assert_sink_payloads(pipeline, next_payload..(next_payload + 99))
    assert_child_effective_flow_control(pipeline, :filter_2, :pull)

    Testing.Pipeline.terminate(pipeline)
  end

  @tag :vibe_coded
  test "buffers queued on a corked auto filter flow once its effective flow control switches to :push" do
    sink_queue_size = 10
    buffers_count = 50

    spec = [
      child(:push_source, PushSource)
      |> via_in(Pad.ref(:input, :push))
      |> child(:filter, AutoFilter)
      |> via_in(:input, target_queue_size: sink_queue_size)
      |> child(:sink, %Testing.Sink{autodemand: false}),
      child(:pull_source, ControlledSource)
      |> via_in(Pad.ref(:input, :pull))
      |> get_child(:filter)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_pipeline_notified(pipeline, :push_source, :playing)
    assert_pipeline_notified(pipeline, :filter, :playing)
    assert_sink_playing(pipeline, :sink)
    assert_child_effective_flow_control(pipeline, :filter, :pull)

    send_buffers(pipeline, :push_source, 1..sink_queue_size)
    send_buffers(pipeline, :push_source, (sink_queue_size + 1)..buffers_count)

    Testing.Pipeline.execute_actions(pipeline, remove_children: :pull_source)
    assert_pipeline_notified(pipeline, :filter, {:pad_removed, Pad.ref(:input, :pull)})
    assert_child_effective_flow_control(pipeline, :filter, :push)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, buffers_count})
    assert_sink_payloads(pipeline, 1..buffers_count)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)

    Testing.Pipeline.terminate(pipeline)
  end

  defp send_buffers(pipeline, source, payloads) do
    buffers = Enum.map(payloads, &%Membrane.Buffer{payload: &1})
    Testing.Pipeline.notify_child(pipeline, source, buffer: {:output, buffers})
  end

  defp assert_sink_payloads(pipeline, payloads) do
    Enum.each(payloads, fn payload ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == payload
    end)
  end

  defp assert_child_effective_flow_control(pipeline, child_name, expected) do
    child_state =
      Testing.Pipeline.get_child_pid!(pipeline, child_name)
      |> :sys.get_state()

    assert child_state.effective_flow_control == expected
  end
end
