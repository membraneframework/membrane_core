defmodule Membrane.Integration.DiamondDetectionTest do
  use ExUnit.Case, async: false

  import ExUnit.Assertions
  import Membrane.ChildrenSpec
  import Mock

  require Membrane.Pad, as: Pad

  alias Membrane.Core.Element.DiamondDetectionController.{DiamondLoggerImpl, PathInGraph}
  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph.Vertex
  alias Membrane.Testing

  defmodule Node do
    use Membrane.Filter

    def_input_pad :input,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :manual,
      demand_unit: :buffers

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :manual

    @impl true
    def handle_demand(_pad, _demand, _unit, _ctx, state), do: {[], state}
  end

  test "simple scenario" do
    with_mock DiamondLoggerImpl, log_diamond: fn _path_a, _path_b -> :ok end do
      spec = [
        child(:source, Node)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:filter, Node)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:sink, Node),
        get_child(:source)
        |> via_out(Pad.ref(:output, 2))
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:sink)
      ]

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      Process.sleep(1500)

      assert [{_element_pid, {DiamondLoggerImpl, :log_diamond, [path_a, path_b]}, :ok}] =
               call_history(DiamondLoggerImpl)

      "#PID" <> inspected_pipeline = inspect(pipeline)

      [shorter_path, longer_path] = Enum.sort_by([path_a, path_b], &length/1)

      assert [
               %Vertex{
                 component_path: ^inspected_pipeline <> "/:sink",
                 input_pad_ref: {Membrane.Pad, :input, 1}
               },
               %Vertex{
                 component_path: ^inspected_pipeline <> "/:filter",
                 input_pad_ref: {Membrane.Pad, :input, 1},
                 output_pad_ref: {Membrane.Pad, :output, 1}
               },
               %Vertex{
                 component_path: ^inspected_pipeline <> "/:source",
                 output_pad_ref: {Membrane.Pad, :output, 1}
               }
             ] = longer_path

      assert [
               %Vertex{
                 component_path: ^inspected_pipeline <> "/:sink",
                 input_pad_ref: {Membrane.Pad, :input, 2}
               },
               %Vertex{
                 component_path: ^inspected_pipeline <> "/:source",
                 output_pad_ref: {Membrane.Pad, :output, 2}
               }
             ] = shorter_path

      Testing.Pipeline.terminate(pipeline)
    end
  end
end
