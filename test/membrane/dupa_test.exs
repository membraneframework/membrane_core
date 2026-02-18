defmodule Membrane.DupaTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Mock

  alias Membrane.Core.Element.DiamondDetectionController.DiamondLogger
  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph.Vertex
  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule MockSource do
    use Membrane.Source

    def_output_pad :output,
      accepted_format: _any,
      flow_control: :push
  end

  defmodule MyPipeline do
    use Membrane.Pipeline

    alias Membrane.Testing
    alias Membrane.DupaTest.MockSource

    @impl true
    def handle_init(_ctx, _opts) do
      crash_group_spec = {
        for i <- 2..5 do
          child({:connector, i}, Membrane.Connector)
        end,
        group: :my_group, crash_group_mode: :temporary
      }

      children_beyond_crash_group = [
        child(:source, MockSource)
        |> child({:connector, 1}, Membrane.Connector),
        child({:connector, 6}, Membrane.Connector)
        |> child(:sink, Testing.Sink)
      ]

      connector_links =
        for i <- 1..5 do
          get_child({:connector, i})
          |> get_child({:connector, i + 1})
        end

      spec = [crash_group_spec, children_beyond_crash_group, connector_links]

      {[spec: spec], %{}}
    end

    @impl true
    def handle_child_terminated(child, context, state) do
      {child, context} |> IO.inspect(label: "HANDLE CHILD TERMINATED", limit: :infinity)
      {[], state}
    end

    @impl true
    def handle_crash_group_down(group_name, context, state) do
      {group_name, context} |> IO.inspect(label: "HANDLE CRASH GROUP DOWN", limit: :infinity)
      {[], state}
    end

    @impl true
    def handle_child_pad_removed(child, pad, context, state) do
      {child, pad, context} |> IO.inspect(label: "HANDLE CHILD PAD REMOVED", limit: :infinity)
      {[], state}
    end
  end

  test "dupa" do
    pipeline = Testing.Pipeline.start_link_supervised!(module: MyPipeline)

    Process.sleep(1500)

    {:ok, connector_pid} = Testing.Pipeline.get_child_pid(pipeline, {:connector, 3})
    Process.exit(connector_pid, :kill)

    Process.sleep(1500)
    Testing.Pipeline.terminate(pipeline)
  end
end
