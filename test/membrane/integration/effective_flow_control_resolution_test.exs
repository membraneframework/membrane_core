defmodule Membrane.Integration.EffectiveFlowControlResolutionTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule AutoFilter do
    use Membrane.Filter

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
      {[forward: buffer], state}
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

  test "effective_flow_control switches between :push and :pull" do
    spec =
      Enum.reduce(
        1..10,
        child(:push_source, PushSource),
        fn idx, last_child -> last_child |> child({:filter, idx}, AutoFilter) end
      )

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(500)

    for _i <- 1..5 do
      Testing.Pipeline.execute_actions(pipeline,
        spec: child(:pull_source, PullSource) |> get_child({:filter, 1})
      )

      Process.sleep(500)

      for idx <- 1..10 do
        assert_child_effective_flow_control(pipeline, {:filter, idx}, :pull)
      end

      Testing.Pipeline.execute_actions(pipeline, remove_children: :pull_source)
      Process.sleep(500)

      for idx <- 1..10 do
        assert_child_effective_flow_control(pipeline, {:filter, idx}, :push)
      end
    end

    Testing.Pipeline.terminate(pipeline)
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

  defp assert_child_effective_flow_control(pipeline, child_name, expected) do
    child_state =
      Testing.Pipeline.get_child_pid!(pipeline, child_name)
      |> :sys.get_state()

    assert child_state.effective_flow_control == expected
  end
end
