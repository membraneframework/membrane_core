defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case
  import Membrane.ParentSpec
  import Membrane.Testing.Assertions
  alias Membrane.ParentSpec

  alias Membrane.Support.Distributed.{Sink, Source}

  setup do
    hostname = start_nodes()
    on_exit(fn -> kill_node(hostname) end)
    [hostname: hostname]
  end

  test "if distributed pipeline works properly", context do
    {:ok, pid} = Membrane.Testing.Pipeline.start([])

    assert_pipeline_playback_changed(pid, _, :playing)

    Membrane.Testing.Pipeline.execute_actions(pid, playback: :stopped)

    assert_pipeline_playback_changed(pid, _, :stopped)

    Membrane.Testing.Pipeline.execute_actions(pid,
      spec: %ParentSpec{
        children: [
          source: %Source{output: [1, 2, 3, 4, 5]}
        ],
        node: :"first@127.0.0.1"
      }
    )

    Membrane.Testing.Pipeline.execute_actions(pid,
      spec: %ParentSpec{
        children: [
          sink: Sink
        ],
        links: [
          link(:source)
          |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
          |> to(:sink)
        ],
        node: context.hostname
      }
    )

    Membrane.Testing.Pipeline.execute_actions(pid, playback: :playing)
    assert_pipeline_playback_changed(pid, _, :playing)
    assert_end_of_stream(pid, :sink)
  end

  defp start_nodes() do
    :net_kernel.start([:"first@127.0.0.1"])
    {:ok, _pid, hostname} = :peer.start(%{hostname: :"127.0.0.1", name: :second})
    :rpc.call(hostname, :code, :add_paths, [:code.get_path()])
    hostname
  end

  defp kill_node(node) do
    :rpc.call(node, :init, :stop, [])
  end
end
