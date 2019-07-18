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
               filter: %Filter{target: self()},
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    assert_receive {:filter_pid, filter_pid}
    assert Process.alive?(filter_pid)

    send(pid, {:remove_child, :filter})
    :timer.sleep(1000)

    assert_receive :element_shutting_down
    refute Process.alive?(filter_pid)

    assert Pipeline.stop(pid) == :ok
  end

  test "Element can be removed when pipeline is in playing state" do
    assert {:ok, pid} =
             Pipeline.start_link(ChildRemovalTest.Pipeline, %{
               source: Source,
               filter: %Filter{target: self()},
               sink: %Sink{target: self(), autodemand: false},
               target: self()
             })

    assert_receive {:filter_pid, filter_pid}
    assert Process.alive?(filter_pid)

    assert Pipeline.play(pid) == :ok
    assert_receive :playing

    send(pid, {:child_msg, :sink, {:make_demand, 10}})
    assert_receive :buffer_in_filter

    send(pid, {:remove_child, :filter})

    assert_receive :element_shutting_down
    refute Process.alive?(filter_pid)

    assert Pipeline.stop(pid) == :ok
  end
end
