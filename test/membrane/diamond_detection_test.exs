defmodule Membrane.DiamondDetectionTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Mock

  alias Membrane.Core.Element.DiamondDetectionController.DiamondLogger
  alias Membrane.Core.Element.DiamondDetectionController.PathInGraph.Vertex
  alias Membrane.Testing

  require Membrane.Pad, as: Pad

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

  test "diamond detection algorithm" do
    with_mock DiamondLogger, log_diamond: fn _path_a, _path_b -> :ok end do
      # a -> b -> c and a -> c
      spec = [
        child(:a, Node)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:b, Node)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:c, Node),
        get_child(:a)
        |> via_out(Pad.ref(:output, 2))
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:c)
      ]

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      Process.sleep(1500)

      assert [{_element_pid, {DiamondLogger, :log_diamond, [path_a, path_b]}, :ok}] =
               call_history(DiamondLogger)

      "#PID" <> pipeline_id = inspect(pipeline)
      pipeline_name = "Pipeline#{pipeline_id}"

      [shorter_path, longer_path] = Enum.sort_by([path_a, path_b], &length/1)

      # assert a -> b -> c
      assert [
               %Vertex{
                 component_path: ^pipeline_name <> "/:c",
                 input_pad_ref: {Membrane.Pad, :input, 1}
               },
               %Vertex{
                 component_path: ^pipeline_name <> "/:b",
                 input_pad_ref: {Membrane.Pad, :input, 1},
                 output_pad_ref: {Membrane.Pad, :output, 1}
               },
               %Vertex{
                 component_path: ^pipeline_name <> "/:a",
                 output_pad_ref: {Membrane.Pad, :output, 1}
               }
             ] = longer_path

      # assert a -> c
      assert [
               %Vertex{
                 component_path: ^pipeline_name <> "/:c",
                 input_pad_ref: {Membrane.Pad, :input, 2}
               },
               %Vertex{
                 component_path: ^pipeline_name <> "/:a",
                 output_pad_ref: {Membrane.Pad, :output, 2}
               }
             ] = shorter_path

      # d -> a -> b -> c and a -> c
      spec =
        child(:d, Node)
        |> via_out(Pad.ref(:output, 3))
        |> via_in(Pad.ref(:input, 3))
        |> get_child(:a)

      Testing.Pipeline.execute_actions(pipeline, spec: spec)

      Process.sleep(1500)

      # adding this link shouldn't trigger logging a diamond
      assert call_history(DiamondLogger) |> length() == 1

      # d -> a -> b -> c and a -> c and d -> c
      spec =
        get_child(:d)
        |> via_out(Pad.ref(:output, 4))
        |> via_in(Pad.ref(:input, 4))
        |> get_child(:c)

      Testing.Pipeline.execute_actions(pipeline, spec: spec)

      Process.sleep(1500)

      # there should be one or two new logged diamonds, depending on the race condition
      assert [_old_entry | new_entries] = call_history(DiamondLogger)
      assert length(new_entries) in [1, 2]

      new_entries
      |> Enum.flat_map(fn {_element_pid, {DiamondLogger, :log_diamond, [path_a, path_b]}, :ok} ->
        [path_a, path_b]
      end)
      |> Enum.each(fn path ->
        assert %{component_path: ^pipeline_name <> "/:c"} = List.first(path)
        assert %{component_path: ^pipeline_name <> "/:d"} = List.last(path)
      end)

      Testing.Pipeline.terminate(pipeline)
    end
  end
end
