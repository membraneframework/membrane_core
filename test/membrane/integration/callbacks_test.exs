defmodule Membrane.Integration.CallbacksTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.Testing

  defmodule PadlessElement do
    use Membrane.Endpoint
  end

  defmodule PadlessElementPipeline do
    use Membrane.Pipeline
    alias Membrane.Integration.CallbacksTest.PadlessElement

    @impl true
    def handle_child_terminated(child_name, ctx, state) do
      assert not is_map_key(ctx.children, child_name)
      {[spec: child(child_name, PadlessElement)], state}
    end
  end

  test "handle_child_terminated" do
    pipeline = Testing.Pipeline.start_link_supervised!(module: PadlessElementPipeline)

    Testing.Pipeline.execute_actions(pipeline, spec: child(:element, PadlessElement))
    first_pid = Testing.Pipeline.get_child_pid!(pipeline, :element)
    refute_child_terminated(pipeline, :element, 500)

    Testing.Pipeline.execute_actions(pipeline, remove_children: :element)
    assert_child_terminated(pipeline, :element)
    second_pid = Testing.Pipeline.get_child_pid!(pipeline, :element)

    assert first_pid != second_pid

    Testing.Pipeline.terminate(pipeline)
  end

  defmodule CrashingFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_playing(_ctx, state) do
      Process.send_after(self(), :raise, 500)
      {[], state}
    end

    @impl true
    def handle_info(:raise, _ctx, _state) do
      raise "Raising"
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      {[buffer: {:output, buffer}], state}
    end
  end

  defmodule CallbacksOrderAssertingPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, _opts) do
      static_spec =
        [
          child(:source, %Membrane.Testing.Source{output: [1, 2, 3]})
          |> child(:connector1, Membrane.Connector),
          child(:connector2, Membrane.Connector)
          |> child(:sink, Membrane.Debug.Sink)
        ]

      crash_group_spec =
        get_child(:connector1)
        |> child(:filter1, Membrane.Debug.Filter)
        |> child(:filter2, CrashingFilter)
        |> child(:filter3, Membrane.Debug.Filter)
        |> get_child(:connector2)

      state = %{crash_group_children: MapSet.new([:filter1, :filter2, :filter3])}

      {[
         spec: static_spec,
         spec: {crash_group_spec, group: :crash_group, crash_group_mode: :temporary}
       ], state}
    end

    @impl true
    def handle_child_terminated(:filter2, ctx, state) do
      assert ctx.crash_initiator == :filter2
      assert ctx.group_name == :crash_group
      assert match?({%RuntimeError{message: "Raising"}, _stacktrace}, ctx.exit_reason)
      state = %{crash_group_children: MapSet.delete(state.crash_group_children, :filter2)}
      {[], state}
    end

    @impl true
    def handle_child_terminated(child, ctx, state) do
      assert ctx.exit_reason == {:shutdown, :membrane_crash_group_kill}
      assert ctx.crash_initiator == :filter2
      assert ctx.group_name == :crash_group
      state = %{crash_group_children: MapSet.delete(state.crash_group_children, child)}
      {[], state}
    end

    @impl true
    def handle_crash_group_down(_group_id, _ctx, state) do
      assert MapSet.size(state.crash_group_children) == 0
      {[terminate: :normal], state}
    end
  end

  test "handle_child_terminated and handle_crash_group_down in proper order" do
    pipeline = Testing.Pipeline.start_link_supervised!(module: CallbacksOrderAssertingPipeline)
    Process.monitor(pipeline)

    receive do
      {:DOWN, _ref, _process, ^pipeline, _reason} -> :ok
    end
  end

  defmodule BinWithTwoChildren do
    use Membrane.Bin

    alias Membrane.Integration.CallbacksTest.PadlessElement

    @impl true
    def handle_init(_ctx, _opts) do
      {[spec: [child(:child_a, PadlessElement), child(:child_b, PadlessElement)]], %{}}
    end

    @impl true
    def handle_playing(ctx, state) do
      {[notify_parent: {:children_pids, ctx.children.child_a.pid, ctx.children.child_b.pid}],
       state}
    end
  end

  defmodule BinTerminationPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_child_notification({:children_pids, a_pid, b_pid}, :bin, _ctx, state) do
      {[], %{state | a_pid: a_pid, b_pid: b_pid}}
    end

    @impl true
    def handle_child_terminated(:bin, _ctx, state) do
      send(
        state.test_pid,
        {:terminated, Process.alive?(state.a_pid), Process.alive?(state.b_pid)}
      )

      {[], state}
    end
  end

  test "handle_child_terminated fires only after bin's subprocess_supervisor dies, ensuring bin's children are already dead" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: BinTerminationPipeline,
        custom_args: %{test_pid: self(), a_pid: nil, b_pid: nil}
      )

    Testing.Pipeline.execute_actions(pipeline,
      spec: {child(:bin, BinWithTwoChildren), group: :bin_group, crash_group_mode: :temporary}
    )

    assert_pipeline_notified(pipeline, :bin, {:children_pids, _a_pid, _b_pid})

    Testing.Pipeline.get_child_pid!(pipeline, :bin)
    |> Process.exit(:crash)

    assert_receive {:terminated, false, false}, 1000

    Testing.Pipeline.terminate(pipeline)
  end
end
