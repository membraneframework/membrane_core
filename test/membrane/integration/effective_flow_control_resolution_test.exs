defmodule Membrane.Integration.EffectiveFlowControlResolutionTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule DynamicFilter do
    use Membrane.Filter

    def_input_pad :input, availability: :on_request, accepted_format: _any
    def_output_pad :output, availability: :on_request, accepted_format: _any

    @impl true
    def handle_playing(_ctx, state) do
      {[notify_parent: :playing], state}
    end
  end

  defmodule DynamicSource do
    use Membrane.Source

    def_output_pad :push_output, accepted_format: _any, flow_control: :push
    def_output_pad :pull_output, accepted_format: _any, flow_control: :manual

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state), do: {[], state}
  end

  @tag :dupa
  test "effective_flow_control is resolved in simple scenario " do
    spec_beggining = [
      child({:filter_a, 0}, DynamicFilter),
      child({:filter_b, 0}, DynamicFilter)
    ]

    spec =
      Enum.reduce(1..10, spec_beggining, fn idx, [predecessor_a, predecessor_b] ->
        [
          predecessor_a
          |> child({:filter_a, idx}, DynamicFilter),
          predecessor_b
          |> child({:filter_b, idx}, DynamicFilter)
        ]
      end)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(1000)

    for idx <- 0..10, filter_type <- [:filter_a, :filter_b] do
      child = {filter_type, idx}

      assert_pipeline_notified(pipeline, child, :playing)

      child_pid = Testing.Pipeline.get_child_pid!(pipeline, child)
      child_state = :sys.get_state(child_pid)

      assert child_state.effective_flow_control == :undefined
    end

    Testing.Pipeline.execute_actions(pipeline,
      spec: [
        child(:source, DynamicSource) |> via_out(:push_output) |> get_child({:filter_a, 0}),
        get_child(:source) |> via_out(:pull_output) |> get_child({:filter_b, 0})
      ]
    )

    Process.sleep(1000)

    for idx <- 0..10, filter_type <- [:filter_a, :filter_b] do
      child = {filter_type, idx}
      child_pid = Testing.Pipeline.get_child_pid!(pipeline, child)
      child_state = :sys.get_state(child_pid)

      expected = if filter_type == :filter_a, do: :push, else: :pull
      assert child_state.effective_flow_control == expected
    end
  end
end
