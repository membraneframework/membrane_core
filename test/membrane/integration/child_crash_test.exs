defmodule Membrane.Integration.ChildCrashTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Support.ChildCrashTest
  alias Membrane.Testing

  test "Element that is not member of any crash group crashed when pipeline is in playing state" do
    Process.flag(:trap_exit, true)

    assert {:ok, pipeline_pid} =
             Testing.Pipeline.start_link(
               module: ChildCrashTest.Pipeline,
               custom_args: %{
                 sink: Testing.Sink
               }
             )

    ChildCrashTest.Pipeline.add_path(pipeline_pid, [:filter_1_1, :filter_2_1], :source_1)

    [sink_pid, center_filter_pid, filter_1_1_pid, filter_1_2_pid, source_1_pid] =
      [:sink, :center_filter, :filter_1_1, :filter_2_1, :source_1]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    assert_pipeline_playback_changed(pipeline_pid, _, :playing)

    ChildCrashTest.Pipeline.crash_child(filter_1_1_pid)

    # assert all members of pipeline and pipeline itself down
    assert_pid_dead(source_1_pid)
    assert_pid_dead(filter_1_1_pid)
    assert_pid_dead(filter_1_2_pid)
    assert_pid_dead(center_filter_pid)
    assert_pid_dead(sink_pid)

    assert_pid_dead(pipeline_pid)
  end

  test "small pipeline with one crash group test" do
    Process.flag(:trap_exit, true)

    assert {:ok, pipeline_pid} = Testing.Pipeline.start_link(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_path(pipeline_pid, [], :source, {1, :temporary})

    [source_pid, center_filter_pid, sink_pid] =
      [:source, :center_filter, :sink]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    assert_pipeline_playback_changed(pipeline_pid, _, :playing)

    Process.exit(source_pid, :crash)
    # member of group is dead
    assert_pid_dead(source_pid)

    # other parts of pipeline are alive
    assert_pid_alive(source_pid)
    assert_pid_alive(center_filter_pid)
    assert_pid_alive(sink_pid)
    assert_pid_alive(pipeline_pid)

    assert_pipeline_crash_group_down(pipeline_pid, 1)

    assert :ok == Testing.Pipeline.terminate(pipeline_pid, blocking?: true)
  end

  test "Crash group consisting of bin crashes" do
    Process.flag(:trap_exit, true)

    assert {:ok, pipeline_pid} = Testing.Pipeline.start_link(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_1, :source_1, {1, :temporary})

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_2, :source_2, {2, :temporary})

    ChildCrashTest.Pipeline.add_bin(pipeline_pid, :bin_3, :source_3, {3, :temporary})

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
        :bin_1,
        :bin_2,
        :bin_3,
        :source_1,
        :source_2,
        :source_3
      ]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    assert_pipeline_playback_changed(pipeline_pid, _, :playing)

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

    assert :ok == Testing.Pipeline.terminate(pipeline_pid, blocking?: true)
  end

  test "Crash two groups one after another" do
    Process.flag(:trap_exit, true)

    assert {:ok, pipeline_pid} = Testing.Pipeline.start_link(module: ChildCrashTest.Pipeline)

    ChildCrashTest.Pipeline.add_path(
      pipeline_pid,
      [:filter_1_1, :filter_2_1],
      :source_1,
      {1, :temporary}
    )

    ChildCrashTest.Pipeline.add_path(
      pipeline_pid,
      [:filter_1_2, :filter_2_2],
      :source_2,
      {2, :temporary}
    )

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
        :filter_1_1,
        :filter_2_1,
        :source_1,
        :filter_1_2,
        :filter_2_2,
        :source_2
      ]
      |> Enum.map(&get_pid_and_link(&1, pipeline_pid))

    assert_pipeline_playback_changed(pipeline_pid, _, :playing)

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

    assert :ok == Testing.Pipeline.terminate(pipeline_pid, blocking?: true)
  end

  defmodule DynamicEndpoint do
    use Membrane.Endpoint

    def_input_pad :input, caps: :any, demand_mode: :auto, demand_unit: :buffers, availability: :on_request
    def_output_pad :output, caps: :any, demand_mode: :auto, demand_unit: :buffers, availability: :on_request

    @impl true
    def handle_init(_opts) do
      {{:ok, notify: {:child_pid, self()}}, %{}}
    end
  end

  @tag :dupa
  test "Crash group and termminate pipeilne" do
    import Membrane.ParentSpec

    {:ok, pipeline} = Testing.Pipeline.start_link(children: [element_1: DynamicEndpoint])

    assert_pipeline_notified(pipeline, :element_1, {:child_pid, _child_pid})

    spec = %Membrane.ParentSpec{
      children: [element_2: DynamicEndpoint],
      links: [link(:element_2) |> to(:element_1)],
      crash_group: {:group, :temporary}
    }

    Testing.Pipeline.execute_actions(pipeline, spec: spec)

    assert_pipeline_notified(pipeline, :element_2, {:child_pid, element_2_pid})

    Process.exit(element_2_pid, :kill)
    Process.sleep(1000)

    ref = Process.monitor(pipeline)
    assert :ok == Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert_receive {:DOWN, ^ref, _process, _pid, _reason}
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
