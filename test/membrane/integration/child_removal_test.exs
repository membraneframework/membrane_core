defmodule Membrane.Integration.ChildRemovalTest do
  use ExUnit.Case, async: false
  use Bunch
  alias Membrane.Support.ChildRemovalTest
  alias Membrane.Core.Element.PlaybackBuffer
  alias Membrane.Buffer
  alias ChildRemovalTest.Filter
  alias Membrane.Testing.{Source, Sink}
  alias Membrane.Pipeline

  test "Element can be removed when pipeline is in stopped state" do
    assert {:ok, pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Source,
               filter1: %Filter{target: self(), ref: 1},
               filter2: %Filter{target: self(), ref: 2},
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [1, 2]
      |> Enum.map(&get_filter_pid/1)

    send(pid, {:remove_child, :filter1})

    assert_receive :element_shutting_down
    assert_pid_dead(filter_pid1)
    assert Process.alive?(filter_pid2)
  end

  test "Element can be removed when pipeline is in playing state" do
    assert {:ok, pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Source,
               filter1: %Filter{target: self(), ref: 1},
               filter2: %Filter{target: self(), ref: 2},
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [1, 2]
      |> Enum.map(&get_filter_pid/1)

    assert Pipeline.play(pid) == :ok
    assert_receive :playing

    send(pid, {:child_msg, :sink, {:make_demand, 10}})
    assert_receive :buffer_in_filter

    send(pid, {:remove_child, :filter1})

    assert_receive :element_shutting_down
    assert_pid_dead(filter_pid1)
    assert Process.alive?(filter_pid2)

    stop_pipeline(pid)
  end

  @doc """
  In this scenario we make filter2 switch between preapre and playing state slowly
  so that it has to store incoming buffers in PlaybackBuffer. When the filter1 dies,
  and filter2 tries to actually enter playing it SHOULD NOT have any buffers there yet.
  """
  test "When PlaybackBuffer is evaluated there is no buffers from removed element" do
    assert {:ok, pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Source,
               filter1: %Filter{target: self(), ref: 1},
               filter2: %Filter{
                 target: self(),
                 playing_delay: prepared_to_playing_delay(),
                 ref: 2
               },
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [1, 2]
      |> Enum.map(&get_filter_pid/1)

    assert Pipeline.play(pid) == :ok
    wait_for_neighbours_state_change()
    send(pid, {:child_msg, :sink, {:make_demand, 30}})
    wait_for_buffer_fillup()
    Filter.deactivate_demands_on_input1(filter_pid2)

    send(pid, {:remove_child, :filter1})

    assert_receive :element_shutting_down
    assert_pid_dead(filter_pid1)
    assert_pid_alive(filter_pid2)

    stop_pipeline(pid)
  end

  test "When PlaybackBuffer is evaluated elements from the other than deleted elements remain untouched" do
    source_buf_gen = get_named_buf_gen(:source)
    extra_source_buf_gen = get_named_buf_gen(:extra_source)

    assert {:ok, pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: %Source{actions_generator: source_buf_gen},
               extra_source: %Source{actions_generator: extra_source_buf_gen},
               filter1: %Filter{target: self(), ref: 1},
               filter2: %Filter{
                 target: self(),
                 playing_delay: prepared_to_playing_delay(),
                 ref: 2
               },
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    [filter_pid1, filter_pid2] =
      [1, 2]
      |> Enum.map(&get_filter_pid/1)

    assert Pipeline.play(pid) == :ok
    wait_for_neighbours_state_change()
    send(pid, {:child_msg, :sink, {:make_demand, 30}})
    wait_for_buffer_fillup()
    Filter.deactivate_demands_on_input1(filter_pid2)

    send(pid, {:remove_child, :filter1})

    assert_receive :element_shutting_down
    assert_pid_dead(filter_pid1)

    %PlaybackBuffer{q: q} = :sys.get_state(filter_pid2).playback_buffer
    refute Enum.empty?(q)
    assert all_buffers_from?(q, :extra_source)

    assert_pid_alive(filter_pid2)

    stop_pipeline(pid)
  end

  defp stop_pipeline(pid) do
    assert Pipeline.stop(pid) == :ok
    assert_receive :pipeline_stopped, 500
  end

  defp assert_pid_dead(pid) do
    assert_receive {:DOWN, _, :process, ^pid, :normal}
  end

  defp assert_pid_alive(pid) do
    refute_receive {:DOWN, _, :process, ^pid, _}
    assert Process.alive?(pid)
  end

  defp get_filter_pid(ref) do
    assert_receive {:filter_pid, ^ref, pid}
    Process.monitor(pid)
    pid
  end

  defp prepared_to_playing_delay, do: 300

  defp wait_for_buffer_fillup, do: :timer.sleep(round(prepared_to_playing_delay() / 3))

  defp wait_for_neighbours_state_change, do: :timer.sleep(round(prepared_to_playing_delay() / 3))

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
    |> Enum.filter(fn {el_name, _} -> el_name == :buffer end)
    |> Enum.map(fn {:buffer, buf} -> buf end)
    |> Enum.all?(&buffer_with_name?(&1, source))
  end

  defp buffer_with_name?([%Buffer{metadata: %{source_name: name}}, _pad], name), do: true

  defp buffer_with_name?([list, _pad], name),
    do: Enum.all?(list, fn %Buffer{metadata: %{source_name: name2}} -> name == name2 end)
end
