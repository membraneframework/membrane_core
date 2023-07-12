defmodule Membrane.Integration.ChildSpawnTest do
  use Bunch
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Core.Message
  alias Membrane.Testing

  require Message

  defmodule PipelineWhichDoesntPlayOnStartup do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, spec) do
      {[spec: spec], %{}}
    end
  end

  defmodule SinkThatNotifiesParent do
    use Membrane.Sink

    def_input_pad :input,
      flow_control: :manual,
      demand_unit: :buffers,
      accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts) do
      {[notify_parent: :message_from_sink], %{}}
    end
  end

  defmodule SinkWithDynamicPads do
    use Membrane.Sink

    def_input_pad :input,
      flow_control: :manual,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :on_request
  end

  defmodule BinWithDynamicPads do
    use Membrane.Bin

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      spec =
        child({:source, pad}, %Testing.Source{output: [1, 2, 3]})
        |> bin_output(pad)

      {[spec: spec], state}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      {[remove_children: {:source, pad}], state}
    end
  end

  test "if child/4 doesn't spawn child with a given name if there is already a child with given name among the children
  and the `get_if_exists` option is enabled" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: [child(:sink, SinkWithDynamicPads)]
      )

    spec =
      child(:source, %Testing.Source{output: [1, 2, 3]})
      |> child(:sink, SinkThatNotifiesParent, get_if_exists: true)

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)

    refute_pipeline_notified(pipeline_pid, :sink, :message_from_sink)
  end

  test "if child/4 spawns a new child with a given name if there is no child with given name among the children
  and the `get_if_exists` option is enabled" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: []
      )

    spec =
      child(:source, %Testing.Source{output: [1, 2, 3]})
      |> child(:sink, Testing.Sink, get_if_exists: true)

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)

    for payload <- [1, 2, 3] do
      assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: ^payload})
    end
  end

  test "if child/3 doesn't spawn child with a given name if there is already a child with given name among the children
  and the `get_if_exists` option is enabled" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: [child(:source, BinWithDynamicPads)]
      )

    spec =
      child(:source, %Testing.Source{output: ["a", "b", "c"]}, get_if_exists: true)
      |> child(:sink, Testing.Sink)

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)

    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 1})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 2})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 3})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "a"})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "b"})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "c"})
  end

  test "if child/3 spawns a new child with a given name if there is no child with given name among the children
  and the `get_if_exists` option is enabled" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: []
      )

    spec =
      child(:source, %Testing.Source{output: [1, 2, 3]})
      |> child(:sink, Testing.Sink, get_if_exists: true)

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)

    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 1})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 2})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 3})
  end

  test "if the pipeline raises an exception when a child with the same name as an exisiting children group is added" do
    pipeline_pid = Testing.Pipeline.start_supervised!()
    pipeline_ref = Process.monitor(pipeline_pid)

    spec1 = child(:source, %Testing.Source{output: [1, 2, 3]}) |> child(:sink, Testing.Sink)
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec1)

    spec2 = {child(:another_source, %Testing.Source{output: [1, 2, 3]}), group: :source}

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec2)
    assert_receive {:DOWN, ^pipeline_ref, :process, ^pipeline_pid, {reason, _stack_trace}}
    assert reason.message =~ ~r/Cannot create children groups with ids: \[:source\]/
    Testing.Pipeline.terminate(pipeline_pid)
  end

  test "if the pipeline raises an exception when a children group with the same name as an exisiting child is added" do
    pipeline_pid = Testing.Pipeline.start_supervised!()
    pipeline_ref = Process.monitor(pipeline_pid)

    spec1 =
      {child(:source, %Testing.Source{output: [1, 2, 3]}) |> child(:sink, Testing.Sink),
       group: :first_group}

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec1)

    spec2 = child(:first_group, %Testing.Source{output: [1, 2, 3]})
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec2)
    assert_receive {:DOWN, ^pipeline_ref, :process, ^pipeline_pid, {reason, _stack_trace}}
    assert reason.message =~ ~r/Cannot spawn children with names: \[:first_group\]/
    Testing.Pipeline.terminate(pipeline_pid)
  end

  test "if the pipeline raises an exception when a children group and a child with the same names are added" do
    pipeline_pid = Testing.Pipeline.start_supervised!()
    pipeline_ref = Process.monitor(pipeline_pid)

    spec =
      {child(:first_group, %Testing.Source{output: [1, 2, 3]}) |> child(:sink, Testing.Sink),
       group: :first_group}

    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)
    assert_receive {:DOWN, ^pipeline_ref, :process, ^pipeline_pid, {reason, _stack_trace}}

    assert reason.message =~
             ~r/Cannot proceed, since the children group ids and children names created in this process are duplicating: \[:first_group\]/

    Testing.Pipeline.terminate(pipeline_pid)
  end

  test "if children can be spawned anonymously" do
    pipeline_pid = Testing.Pipeline.start_supervised!()
    spec = child(%Testing.Source{output: [1, 2, 3]}) |> child(Testing.Sink)
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)

    Testing.Pipeline.terminate(pipeline_pid)
  end
end
