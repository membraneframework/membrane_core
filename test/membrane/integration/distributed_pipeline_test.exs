defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case

  alias Membrane.Testing
  alias Membrane.Support.Distributed

  import Membrane.Testing.Assertions

  setup do
    {my_node, another_node} = start_nodes()
    on_exit(fn -> kill_node(another_node) end)
    [first_node: my_node, second_node: another_node]
  end

  test "if distributed pipeline works properly", context do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Distributed.Pipeline,
        custom_args: context
      )

    assert_pipeline_notified(pipeline, :sink_bin, :end_of_stream)

    assert context.first_node == node(pipeline)

    assert context.first_node ==
             Testing.Pipeline.get_child_pid!(pipeline, :source)
             |> node()

    assert context.second_node ==
             Testing.Pipeline.get_child_pid!(pipeline, :sink_bin)
             |> node()

    assert context.second_node ==
             Testing.Pipeline.get_child_pid!(pipeline, [:sink_bin, :sink])
             |> node()

    Testing.Pipeline.terminate(pipeline)
  end

  defp start_nodes() do
    System.cmd("epmd", ["-daemon"])
    _start_result = Node.start(:"first@127.0.0.1", :longnames)
    {:ok, _pid, hostname} = :peer.start(%{host: ~c"127.0.0.1", name: :second})
    :rpc.block_call(hostname, :code, :add_paths, [:code.get_path()])
    {node(self()), hostname}
  end

  defp kill_node(node) do
    :rpc.call(node, :init, :stop, [])
  end
end
