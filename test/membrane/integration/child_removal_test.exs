defmodule Membrane.Integration.ChildRemovalTest do
  use Bunch
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Core.Message
  alias Membrane.Pipeline
  alias Membrane.Support.ChildRemovalTest
  alias Membrane.Testing

  require Message

  test "Element can be removed when pipeline is in stopped state" do
    assert {:ok, pipeline_pid} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               module: ChildRemovalTest.Pipeline,
               custom_args: %{
                 source: Testing.Source,
                 filter1: ChildRemovalTest.Filter,
                 filter2: ChildRemovalTest.Filter,
                 filter3: ChildRemovalTest.Filter,
                 sink: Testing.Sink
               }
             })

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(pipeline_pid)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)

    stop_pipeline(pipeline_pid)
  end

  test "Element can be removed when pipeline is in playing state" do
    assert {:ok, pipeline_pid} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               module: ChildRemovalTest.Pipeline,
               custom_args: %{
                 source: Testing.Source,
                 filter1: ChildRemovalTest.Filter,
                 filter2: ChildRemovalTest.Filter,
                 filter3: ChildRemovalTest.Filter,
                 sink: Testing.Sink
               }
             })

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    :ok = Pipeline.play(pipeline_pid)

    assert_pipeline_playback_changed(pipeline_pid, _, :playing)
    assert_pipeline_notified(pipeline_pid, :filter1, :playing)
    assert_pipeline_notified(pipeline_pid, :filter2, :playing)
    assert_pipeline_notified(pipeline_pid, :filter3, :playing)

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)

    stop_pipeline(pipeline_pid)
  end

  @doc """
  In this scenario we make `filter3` switch between prepare and playing state slowly
  so that it has to store incoming buffers in PlaybackBuffer. When the `filter1` dies,
  and `filter2` tries to actually enter playing it SHOULD NOT have any buffers there yet.

  source -- filter1 -- [input1] filter2 -- [input1] filter3 -- sink

  """
  test "When PlaybackBuffer is evaluated there is no buffers from removed element" do
    assert {:ok, pipeline_pid} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               module: ChildRemovalTest.Pipeline,
               custom_args: %{
                 source: Testing.Source,
                 filter1: ChildRemovalTest.Filter,
                 filter2: ChildRemovalTest.Filter,
                 filter3: %ChildRemovalTest.Filter{playing_delay: prepared_to_playing_delay()},
                 sink: Testing.Sink
               }
             })

    Process.monitor(pipeline_pid)

    [filter_pid1, filter_pid2, filter_pid3] =
      [:filter1, :filter2, :filter3]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert Pipeline.play(pipeline_pid) == :ok
    assert_pipeline_playback_changed(pipeline_pid, _, :playing)
    assert_pipeline_notified(pipeline_pid, :filter1, :playing)
    assert_pipeline_notified(pipeline_pid, :filter2, :playing)
    assert_pipeline_notified(pipeline_pid, :filter3, :playing)

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter2)

    assert_pid_dead(filter_pid2)
    assert_pid_alive(filter_pid1)
    assert_pid_alive(filter_pid3)

    stop_pipeline(pipeline_pid)
  end

  #############
  ## HELPERS ##
  #############

  defp stop_pipeline(pid) do
    assert Pipeline.stop_and_terminate(pid) == :ok
    assert_pid_dead(pid)
  end

  defp assert_pid_dead(pid) do
    assert_receive {:DOWN, _, :process, ^pid, :normal}
  end

  defp assert_pid_alive(pid) do
    refute_receive {:DOWN, _, :process, ^pid, _}
  end

  defp get_filter_pid(ref, pipeline_pid) do
    state = :sys.get_state(pipeline_pid)
    pid = state.children[ref].pid
    Process.monitor(pid)
    pid
  end

  defp prepared_to_playing_delay, do: 300
end
