defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  setup do
    {my_node, another_node} = start_nodes()
    on_exit(fn -> kill_node(another_node) end)
    [first_node: my_node, second_node: another_node]
  end

  test "if distributed pipeline works properly", context do
    defmodule Pipeline do
      use Membrane.Pipeline
      alias Membrane.Support.Distributed.{Sink, Source}

      @impl true
      def handle_init(_ctx, opts) do
        first_node = opts[:first_node]
        second_node = opts[:second_node]

        {[
           spec: [
             {child(:source, %Source{output: [1, 2, 3, 4, 5]}), node: first_node},
             {get_child(:source)
              |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
              |> child(:sink, Sink), node: second_node}
           ]
         ], %{}}
      end
    end

    pipeline =
      Membrane.Testing.Pipeline.start_link_supervised!(module: Pipeline, custom_args: context)

    assert_end_of_stream(pipeline, :sink)
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
