defmodule Membrane.Integration.ChildRemovalTest do
  use ExUnit.Case, async: false
  use Bunch

  alias Membrane.Support.ChildRemovalTest
  alias Membrane.Testing

  alias Membrane.Core.Element.PlaybackBuffer
  alias Membrane.Buffer
  alias Membrane.Pipeline

  alias Membrane.Core.Message
  require Message

  test "Element can be removed when pipeline is in stopped state" do
    assert {:ok, pipeline_pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Testing.Source,
               filter1: ChildRemovalTest.Filter,
               filter2: ChildRemovalTest.Filter,
               sink: Testing.Sink,
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [:filter1, :filter2]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter1)

    assert_pid_dead(filter_pid1)
    assert Process.alive?(filter_pid2)
  end

  test "Element can be removed when pipeline is in playing state" do
    assert {:ok, pipeline_pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Testing.Source,
               filter1: ChildRemovalTest.Filter,
               filter2: ChildRemovalTest.Filter,
               sink: Testing.Sink,
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [:filter1, :filter2]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert Pipeline.play(pipeline_pid) == :ok
    assert_receive {:playing, :filter1}
    assert_receive {:playing, :filter2}

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter1)

    assert_pid_dead(filter_pid1)
    assert Process.alive?(filter_pid2)

    stop_pipeline(pipeline_pid)
  end

  @doc """
  In this scenario we make `filter2` switch between preapre and playing state slowly
  so that it has to store incoming buffers in PlaybackBuffer. When the `filter1` dies,
  and `filter2` tries to actually enter playing it SHOULD NOT have any buffers there yet.

  source -- filter1 -- [input1] filter2 -- sink

  """
  test "When PlaybackBuffer is evaluated there is no buffers from removed element" do
    assert {:ok, pipeline_pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Testing.Source,
               filter1: ChildRemovalTest.Filter,
               filter2: %ChildRemovalTest.Filter{
                 playing_delay: prepared_to_playing_delay()
               },
               sink: Testing.Sink,
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [:filter1, :filter2]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert Pipeline.play(pipeline_pid) == :ok
    wait_for_playing(:filter1)
    wait_for_buffer_fillup(filter_pid2, [:input1])

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter1)

    assert_pid_dead(filter_pid1)
    assert_pid_alive(filter_pid2)

    stop_pipeline(pipeline_pid)
  end

  @doc """
  In this scenario we have two sources. One of them (`source`) is pushing data to filter1 and the other one
  (`extra_source`) straight to `filter_2`. ChildRemovalTest.Filter module knows it has to only push ONE start of stream event.
  The test ensures that when we flush buffers from PlaybacBuffer we only flush buffers that came from the deleted
  element.

  source -- filter1 -- [input1] filter2 -- sink
                               [input2]
                                  /
                 extra_source ___/
  """
  test "When element is removed data sent from it is removed from neighbours' playback buffer, other data remain untouched" do
    source_buf_gen = get_named_buf_gen(:source)
    extra_source_buf_gen = get_named_buf_gen(:extra_source)

    assert {:ok, pipeline_pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: %Testing.Source{output: {0, source_buf_gen}},
               extra_source: %Testing.Source{output: {0, extra_source_buf_gen}},
               filter1: ChildRemovalTest.Filter,
               filter2: %ChildRemovalTest.Filter{
                 playing_delay: prepared_to_playing_delay()
               },
               sink: Testing.Sink,
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [:filter1, :filter2]
      |> Enum.map(&get_filter_pid(&1, pipeline_pid))

    assert Pipeline.play(pipeline_pid) == :ok
    wait_for_playing(:filter1)
    wait_for_buffer_fillup(filter_pid2, [:input1, :input2])

    ChildRemovalTest.Pipeline.remove_child(pipeline_pid, :filter1)

    assert_pid_dead(filter_pid1)

    %PlaybackBuffer{q: q} = :sys.get_state(filter_pid2).playback_buffer
    refute Enum.empty?(q)
    assert all_buffers_from?(q, :extra_source)

    assert_pid_alive(filter_pid2)

    stop_pipeline(pipeline_pid)
  end

  #############
  ## HELPERS ##
  #############

  defp stop_pipeline(pid) do
    assert Pipeline.stop(pid) == :ok
    assert_receive :pipeline_stopped, 500
  end

  defp assert_pid_dead(pid) do
    assert_receive {:DOWN, _, :process, ^pid, :normal}
  end

  defp assert_pid_alive(pid) do
    refute_receive {:DOWN, _, :process, ^pid, _}
  end

  defp get_filter_pid(ref, pipeline_pid) do
    state = :sys.get_state(pipeline_pid)
    pid = state.children[ref]
    Process.monitor(pid)
    pid
  end

  defp prepared_to_playing_delay, do: 300

  # Checks if there is at least one item in the playback buffer for each pad specified in `for_pads`
  defp wait_for_buffer_fillup(el_pid, for_pads, timeout \\ 5) do
    1..10
    |> Enum.take_while(fn _ ->
      Process.sleep(timeout)

      %PlaybackBuffer{q: q} = :sys.get_state(el_pid).playback_buffer

      pads_in_buffer =
        q
        |> Enum.filter(fn Message.new(type, _, _) -> type == :buffer end)
        |> Enum.map(fn Message.new(_, _, opts) -> Keyword.get(opts, :for_pad) end)
        |> Enum.dedup()
        |> Enum.sort()

      for_pads_sorted =
        for_pads
        |> Enum.sort()

      pads_in_buffer != for_pads_sorted
    end)
  end

  defp get_named_buf_gen(name) do
    fn cnt, size ->
      cnt..(size + cnt - 1)
      |> Enum.map(fn _cnt ->
        buf = %Buffer{payload: 'a', metadata: %{source_name: name}}
        {:buffer, {:output, buf}}
      end)
      ~> {&1, cnt + size}
    end
  end

  defp all_buffers_from?(q, source) do
    q
    |> Enum.filter(fn Message.new(el_name, _, _) -> el_name == :buffer end)
    |> Enum.map(fn Message.new(:buffer, arg, _opts) -> arg end)
    |> Enum.all?(&buffer_with_name?(&1, source))
  end

  defp buffer_with_name?(list, name),
    do: Enum.all?(list, fn %Buffer{metadata: %{source_name: name2}} -> name == name2 end)

  defp wait_for_playing(el) do
    assert_receive {:playing, ^el}
  end
end
