defmodule Membrane.Integration.ChildSpawnTest do
  use Bunch
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.Buffer
  alias Membrane.ChildrenSpec
  alias Membrane.Core.Message
  alias Membrane.Testing

  require Message

  defmodule PipelineWhichDoesntPlayOnStartup do
    use Membrane.Pipeline

    @impl true
    def handle_init(structure) do
      spec = %ChildrenSpec{structure: structure}
      {{:ok, spec: spec}, %{}}
    end
  end

  defmodule SinkThatNotifiesParent do
    use Membrane.Sink

    def_input_pad :input,
      demand_unit: :buffers,
      caps: :any

    @impl true
    def handle_init(_opts) do
      {{:ok, notify_parent: :message_from_sink}, %{}}
    end
  end

  test "if to_new/3 doesn't spawn child with a given name if there is already a child with given name among the children" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: [spawn_child(:sink, Testing.Sink)]
      )

    structure = [
      spawn_child(:source, %Testing.Source{output: [1, 2, 3]})
      |> to_new(:sink, SinkThatNotifiesParent)
    ]

    spec = %ChildrenSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)
    # a workaround - I need to wait for some time for pads to link, so that not let the
    # "unlinked pads" exception be thrown
    :timer.sleep(1000)
    Testing.Pipeline.execute_actions(pipeline_pid, playback: :playing)
    assert_pipeline_play(pipeline_pid)
    refute_pipeline_notified(pipeline_pid, :sink, :message_from_sink)
  end

  test "if to_new/3 spawns a new child with a given name if there is no child with given name among the children" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: []
      )

    structure = [
      spawn_child(:source, %Testing.Source{output: [1, 2, 3]}) |> to_new(:sink, Testing.Sink)
    ]

    spec = %ChildrenSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec, playback: :playing)
    assert_pipeline_play(pipeline_pid)
  end

  test "if link_new/2 doesn't spawn child with a given name if there is already a child with given name among the children" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: [spawn_child(:source, %Testing.Source{output: [1, 2, 3]})]
      )

    structure = [
      link_new(:source, %Testing.Source{output: [1, 2, 3]}) |> to(:sink, Testing.Sink)
    ]

    spec = %ChildrenSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)
    # a workaround - I need to wait for some time for pads to link, so that not let the
    # "unlinked pads" exception be thrown
    :timer.sleep(1000)
    Testing.Pipeline.execute_actions(pipeline_pid, playback: :playing)
    assert_pipeline_play(pipeline_pid)
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 1})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 2})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 3})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "a"})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "b"})
    refute_sink_buffer(pipeline_pid, :sink, %Buffer{payload: "c"})
  end

  test "if link_new/2 spawns a new child with a given name if there is no child with given name among the children" do
    pipeline_pid =
      Testing.Pipeline.start_link_supervised!(
        module: PipelineWhichDoesntPlayOnStartup,
        custom_args: []
      )

    structure = [
      link_new(:source, %Testing.Source{output: [1, 2, 3]}) |> to(:sink, Testing.Sink)
    ]

    spec = %ChildrenSpec{structure: structure}
    Testing.Pipeline.execute_actions(pipeline_pid, spec: spec)
    # a workaround - I need to wait for some time for pads to link, so that not let the
    # "unlinked pads" exception be thrown
    :timer.sleep(1000)
    Testing.Pipeline.execute_actions(pipeline_pid, playback: :playing)
    assert_pipeline_play(pipeline_pid)
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 1})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 2})
    assert_sink_buffer(pipeline_pid, :sink, %Buffer{payload: 3})
  end
end
