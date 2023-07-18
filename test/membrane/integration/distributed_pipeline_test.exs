defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Support.Distributed
  alias Membrane.Testing

  setup do
    another_node = start_another_node()
    on_exit(fn -> kill_node(another_node) end)
    [first_node: node(self()), second_node: another_node]
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

  defp start_another_node() do
    {:ok, _pid, hostname} = :peer.start(%{host: ~c"127.0.0.1", name: :second})
    :rpc.block_call(hostname, :code, :add_paths, [:code.get_path()])
    hostname
  end

  defp kill_node(node) do
    :rpc.call(node, :init, :stop, [])
  end
end
