defmodule Membrane.Integration.ChildCrashTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.ChildCrashTest
  alias Membrane.Testing

  require Membrane.Pad, as: Pad
  require Membrane.Child, as: Child

  test "Element that is not member of any crash group crashed when pipeline is in playing state" do
    Process.flag(:trap_exit, true)

    assert pipeline_pid =
             Testing.Pipeline.start_link_supervised!(
               module: ChildCrashTest.Pipeline,
               custom_args: %{
                 sink: Testing.Sink
               }
             )

    ChildCrashTest.Pipeline.add_path(pipeline_pid, [:filter_1_1, :filter_2_1], :source_1, 1, nil)

    [sink_pid, center_filter_pid, filter_1_1_pid, filter_2_1_pid, source_1_pid] =
      [
        :sink,
        :center_filter,
        {Membrane.Child, 1, :filter_1_1},
        {Membrane.Child, 1, :filter_2_1},
        {Membrane.Child, 1, :source_1}
      ]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    ChildCrashTest.Pipeline.crash_child(filter_1_1_pid)

    # assert all members of pipeline and pipeline itself down
    assert_pid_dead(source_1_pid)
    assert_pid_dead(filter_1_1_pid)
    assert_pid_dead(filter_2_1_pid)
    assert_pid_dead(center_filter_pid)
    assert_pid_dead(sink_pid)

    assert_pid_dead(pipeline_pid)
  end

  test "small pipeline with one crash group test" do
    Process.flag(:trap_exit, true)

    pipeline_pid = Testing.Pipeline.start_link_supervised!(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_path(pipeline_pid, [], :source, 1, :group_1)

    [source_pid, center_filter_pid, sink_pid] =
      [{Membrane.Child, 1, :source}, :center_filter, :sink]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    Process.exit(source_pid, :crash)
    # member of group is dead
    assert_pid_dead(source_pid)

    # other parts of pipeline are alive
    assert_pid_alive(center_filter_pid)
    assert_pid_alive(sink_pid)
    assert_pid_alive(pipeline_pid)

    assert_pipeline_crash_group_down(pipeline_pid, 1)
  end

  test "Crash group consisting of bin crashes" do
    Process.flag(:trap_exit, true)

    pipeline_pid = Testing.Pipeline.start_link_supervised!(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_1, :source_1, 1)

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_2, :source_2, 2)

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_3, :source_3, 3)

    [
      sink_pid,
      center_filter_pid,
      bin_1_pid,
      bin_2_pid,
      bin_3_pid,
      source_1_pid,
      source_2_pid,
      source_3_pid
    ] =
      [
        :sink,
        :center_filter,
        {Membrane.Child, 1, :bin_1},
        {Membrane.Child, 2, :bin_2},
        {Membrane.Child, 3, :bin_3},
        {Membrane.Child, 1, :source_1},
        {Membrane.Child, 2, :source_2},
        {Membrane.Child, 3, :source_3}
      ]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    filter_1_pid = get_pid(:filter, bin_1_pid)

    ChildCrashTest.Filter.crash(filter_1_pid)

    # assert source 1, bin_1 and filter that is inside of it are dead
    assert_pid_dead(source_1_pid)
    assert_pid_dead(bin_1_pid)

    assert_pid_alive(sink_pid)
    assert_pid_alive(center_filter_pid)
    assert_pid_alive(bin_2_pid)
    assert_pid_alive(bin_3_pid)
    assert_pid_alive(source_2_pid)
    assert_pid_alive(source_3_pid)
    assert_pid_alive(pipeline_pid)
  end

  test "Crash two groups one after another" do
    Process.flag(:trap_exit, true)

    pipeline_pid = Testing.Pipeline.start_link_supervised!(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_path(
      pipeline_pid,
      [:filter_1_1, :filter_2_1],
      :source_1,
      1,
      :temporary
    )

    ChildCrashTest.Pipeline.add_path(
      pipeline_pid,
      [:filter_1_2, :filter_2_2],
      :source_2,
      2,
      :temporary
    )

    # :timer.sleep(3000)
    [
      sink_pid,
      center_filter_pid,
      filter_1_1_pid,
      filter_2_1_pid,
      source_1_pid,
      filter_1_2_pid,
      filter_2_2_pid,
      source_2_pid
    ] =
      [
        :sink,
        :center_filter,
        {Membrane.Child, 1, :filter_1_1},
        {Membrane.Child, 1, :filter_2_1},
        {Membrane.Child, 1, :source_1},
        {Membrane.Child, 2, :filter_1_2},
        {Membrane.Child, 2, :filter_2_2},
        {Membrane.Child, 2, :source_2}
      ]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    ChildCrashTest.Pipeline.crash_child(filter_1_1_pid)

    # assert all members of group are dead
    assert_pid_dead(filter_1_1_pid)
    assert_pid_dead(filter_2_1_pid)
    assert_pid_dead(source_1_pid)

    # assert all other members of pipeline and pipeline itself are alive
    assert_pid_alive(sink_pid)
    assert_pid_alive(center_filter_pid)
    assert_pid_alive(filter_1_2_pid)
    assert_pid_alive(filter_2_2_pid)
    assert_pid_alive(source_2_pid)
    assert_pid_alive(pipeline_pid)

    assert_pipeline_crash_group_down(pipeline_pid, 1)
    refute_pipeline_crash_group_down(pipeline_pid, 2)

    ChildCrashTest.Pipeline.crash_child(filter_1_2_pid)

    # assert all members of group are dead
    assert_pid_dead(filter_1_2_pid)
    assert_pid_dead(filter_2_2_pid)
    assert_pid_dead(source_2_pid)

    # assert all other members of pipeline and pipeline itself are alive
    assert_pid_alive(sink_pid)
    assert_pid_alive(center_filter_pid)
    assert_pid_alive(pipeline_pid)

    assert_pipeline_crash_group_down(pipeline_pid, 2)
  end

  defmodule DynamicElement do
    use Membrane.Endpoint

    def_input_pad :input,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :push

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :push

    @impl true
    def handle_playing(_ctx, _opts) do
      {[notify_parent: :playing], %{}}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    alias Membrane.Integration.ChildCrashTest.DynamicElement
    require Membrane.Pad, as: Pad

    def_input_pad :input,
      accepted_format: _any,
      availability: :on_request

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request

    def_options do_internal_link: [spec: boolean(), default: true]

    @impl true
    def handle_playing(_ctx, _opts) do
      {[notify_parent: :playing], %{}}
    end

    @impl true
    def handle_pad_added(Pad.ref(direction, _id) = pad, _ctx, state) do
      spec =
        if state.do_internal_link do
          [
            {child(direction, DynamicElement), group: :group, crash_group_mode: :temporary},
            get_child(Child.ref(direction, group: :group)) |> bin_output(pad)
          ]
        else
          []
        end

      {[spec: spec, notify_parent: :handle_pad_added], state}
    end
  end

  defmodule OuterBin do
    use Membrane.Bin

    alias Membrane.Integration.ChildCrashTest.Bin

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      spec = child(:bin, Bin) |> bin_output(pad)
      {[spec: spec], state}
    end

    @impl true
    def handle_child_notification(notification, :bin, _ctx, state) do
      {[notify_parent: {:child_notification, notification}], state}
    end

    @impl true
    def handle_child_pad_removed(child, pad, _ctx, state) do
      {[notify_parent: {:child_pad_removed, child, pad}], state}
    end
  end

  describe "When crash group inside a bin crashes" do
    test "bin removes a pad" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec: child(:bin, Bin) |> child(:element, DynamicElement),
          raise_on_child_pad_removed?: false
        )

      assert_pipeline_notified(pipeline, :element, :playing)

      child_ref = Child.ref(:output, group: :group)
      bin_child_pid = Testing.Pipeline.get_child_pid!(pipeline, [:bin, child_ref])
      Process.exit(bin_child_pid, :kill)

      assert_child_pad_removed(pipeline, :bin, Pad.ref(:output, _id))

      Testing.Pipeline.terminate(pipeline)
    end

    test "spec is updated" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:first_bin, %Bin{do_internal_link: false})
            |> child(:second_bin, Bin)
            |> child(:element, DynamicElement),
          raise_on_child_pad_removed?: false
        )

      assert_pipeline_notified(pipeline, :second_bin, :handle_pad_added)
      refute_pipeline_notified(pipeline, :element, :playing)

      child_ref = Child.ref(:output, group: :group)

      Testing.Pipeline.get_child_pid!(pipeline, [:second_bin, child_ref])
      |> Process.exit(:kill)

      assert_child_pad_removed(pipeline, :second_bin, Pad.ref(:output, _id))

      Testing.Pipeline.execute_actions(pipeline, remove_children: :first_bin)

      assert_pipeline_notified(pipeline, :element, :playing)
      assert_pipeline_notified(pipeline, :second_bin, :playing)

      Testing.Pipeline.terminate(pipeline)
    end

    test "bin's parent's parent is notified, if should be" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:bin, OuterBin)
            |> child(:element, DynamicElement),
          raise_on_child_pad_removed?: false
        )

      assert_pipeline_notified(pipeline, :element, :playing)

      inner_element_pid =
        Testing.Pipeline.get_child_pid!(
          pipeline,
          [:bin, :bin, Child.ref(:output, group: :group)]
        )

      Process.exit(inner_element_pid, :kill)

      assert_child_pad_removed(pipeline, :bin, Pad.ref(:output, _id))
      assert_pipeline_notified(pipeline, :bin, {:child_pad_removed, :bin, Pad.ref(:output, _id)})

      Testing.Pipeline.terminate(pipeline)
    end
  end

  test "When crash group crashes, another crash group from this same spec is still living" do
    children_definitions =
      child(:first_bin, %Bin{do_internal_link: false})
      |> child(:second_bin, Bin)
      |> child(:element, DynamicElement)

    spec = [
      {children_definitions, group: :a, crash_group_mode: :temporary},
      {children_definitions, group: :b, crash_group_mode: :temporary}
    ]

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: spec,
        raise_on_child_pad_removed?: false
      )

    assert_pipeline_notified(pipeline, Child.ref(:second_bin, group: :a), :handle_pad_added)

    Testing.Pipeline.get_child_pid!(pipeline, Child.ref(:second_bin, group: :a))
    |> Process.exit(:kill)

    assert_pipeline_crash_group_down(pipeline, :a)
    refute_pipeline_notified(pipeline, Child.ref(:second_bin, group: :b), :playing)

    Testing.Pipeline.execute_actions(pipeline, remove_children: Child.ref(:first_bin, group: :b))

    assert_pipeline_notified(pipeline, Child.ref(:second_bin, group: :b), :playing)
    assert_pipeline_notified(pipeline, Child.ref(:element, group: :b), :playing)

    Testing.Pipeline.terminate(pipeline)
  end

  defp assert_pid_alive(pid) do
    refute_receive {:EXIT, ^pid, _}
  end

  defp assert_pid_dead(pid) do
    assert_receive {:EXIT, ^pid, _}, 2000
  end

  defp get_pid_and_link(ref, pipeline_pid) do
    state = :sys.get_state(pipeline_pid)
    pid = state.children[ref].pid
    :erlang.link(pid)
    pid
  end

  defp get_pid(ref, parent_pid) do
    state = :sys.get_state(parent_pid)
    state.children[ref].pid
  end
end
