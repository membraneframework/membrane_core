defmodule Membrane.Integration.DistributedPipelineTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions

  setup do
    hostname = start_nodes()
    on_exit(fn -> kill_node(hostname) end)
  end

  test "if distributed pipeline works properly" do
    defmodule Pipeline do
      use Membrane.Pipeline
      alias Membrane.Support.Distributed.{Sink, Source}

      @impl true
      def handle_init(_ctx, _opts) do
        {{:ok,
          spec: %ParentSpec{
            children: [
              source: %Source{output: [1, 2, 3, 4, 5]}
            ],
            node: :"first@127.0.0.1"
          },
          spec: %ParentSpec{
            children: [
              sink: Sink
            ],
            links: [
              link(:source)
              |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
              |> to(:sink)
            ],
            node: :"second@127.0.0.1"
          }}, %{}}
      end
    end

    pipeline = Membrane.Testing.Pipeline.start_link_supervised!(module: Pipeline)
    Membrane.Testing.Pipeline.execute_actions(pipeline, playback: :playing)
    assert_pipeline_play(pipeline)
    assert_end_of_stream(pipeline, :sink)
  end

  defp start_nodes() do
    System.cmd("epmd", ["-daemon"])
    {:ok, _pid} = Node.start(:"first@127.0.0.1", :longnames)
    {:ok, _pid, hostname} = :peer.start(%{host: ~c"127.0.0.1", name: :second})
    :rpc.block_call(hostname, :code, :add_paths, [:code.get_path()])
    hostname
  end

  defp kill_node(node) do
    :rpc.call(node, :init, :stop, [])
  end
end
