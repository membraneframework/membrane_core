defmodule Membrane.Integration.ChildRemovalTest do
  use ExUnit.Case, async: false
  use Bunch
  alias Membrane.Support.ChildRemovalTest
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
               filter2: %Filter{target: self(), playing_delay: 300, ref: 2},
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })
    [filter_pid1, filter_pid2] =
    [1, 2]
    |> Enum.map(&get_filter_pid/1)

    assert Pipeline.play(pid) == :ok
    wait_for_state_change()
    send(pid, {:child_msg, :sink, {:make_demand, 30}})
    wait_for_buffer()

    send(pid, {:remove_child, :filter1})

    assert_receive :element_shutting_down
    assert_pid_dead(filter_pid1)

    stop_pipeline(pid)
  end

  defp stop_pipeline(pid) do
    assert Pipeline.stop(pid) == :ok
    assert_receive :pipeline_stopped, 500
  end

  defp assert_pid_dead(pid) do
    assert_receive {:DOWN, _, :process, ^pid, :normal}
  end

  defp wait_for_buffer, do: :timer.sleep(100)

  defp wait_for_state_change, do: :timer.sleep(100)

  defp get_filter_pid(ref) do
    assert_receive {:filter_pid, ^ref, pid}
    Process.monitor(pid)
    pid
  end

end
