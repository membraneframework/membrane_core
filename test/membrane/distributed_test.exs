defmodule DistributedTest do
  use ExUnit.Case
  alias Membrane.ParentSpec
  import Membrane.Testing.Assertions
  alias Membrane.Support.Distributed.{Source, Sink, Pipeline}
  import ParentSpec

  test "if distributed pipeline works properly" do
    {:ok, hostname} = start_nodes()
    {:ok, pid} = Membrane.Testing.Pipeline.start([])

    assert_pipeline_playback_changed(pid, _, :playing)

    Membrane.Testing.Pipeline.execute_actions(pid, playback: :stopped)

    assert_pipeline_playback_changed(pid, _, :stopped)

    Membrane.Testing.Pipeline.execute_actions(pid,
      spec: %ParentSpec{
        children: [
          source: %Membrane.Testing.Source{output: [1, 2, 3, 4, 5]}
        ],
        node: :"first@127.0.0.1"
      }
    )

    Membrane.Testing.Pipeline.execute_actions(pid,
      spec: %ParentSpec{
        children: [
          sink: Sink
        ],
        node: :"first@127.0.0.1"
      }
    )

    Membrane.Testing.Pipeline.execute_actions(pid,
      spec: %ParentSpec{
        links: [
          link(:source)
          |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
          |> to(:sink)
        ]
      }
    )

    Membrane.Testing.Pipeline.execute_actions(pid, playback: :playing)

    assert_pipeline_playback_changed(pid, _, :playing)
    assert_end_of_stream(pid, :sink)
    # kill_nodes(hostname)
  end

  def start_nodes() do
    :net_kernel.start([:"first@127.0.0.1"])
    {:ok, hostname} = :slave.start(:"127.0.0.1", :second)
    :rpc.call(hostname, :code, :add_paths, [:code.get_path()])
    {:ok, hostname}
  end

  def kill_nodes(node) do
    :rpc.call(node, :init, :stop, [])
  end
end
