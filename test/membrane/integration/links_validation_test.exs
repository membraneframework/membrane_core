defmodule Membrane.LinksValidationTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec

  alias Membrane.Pad
  alias Membrane.Testing.Pipeline

  require Membrane.Pad

  defmodule Caps do
    defstruct []
  end

  defmodule StaticPads do
    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input,
        demand_unit: :buffers,
        caps: :any,
        availability: :always,
        mode: :push
    end

    defmodule Source do
      use Membrane.Source

      def_output_pad :output,
        demand_unit: :buffers,
        caps: :any,
        availability: :always,
        mode: :push

      @impl true
      def handle_playing(_ctx, state) do
        caps = %Membrane.LinksValidationTest.Caps{}
        {{:ok, caps: {:output, caps}}, state}
      end
    end
  end

  defmodule DynamicPads do
    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input,
        demand_unit: :buffers,
        caps: :any,
        availability: :on_request,
        mode: :push
    end

    defmodule Source do
      use Membrane.Source

      def_output_pad :output,
        demand_unit: :buffers,
        caps: :any,
        availability: :on_request,
        mode: :push

      @impl true
      def handle_playing(_ctx, state) do
        caps = %Membrane.LinksValidationTest.Caps{}
        {{:ok, caps: {:output, caps}}, state}
      end
    end
  end

  describe "returning a spec with many links to this same" do
    test "static pads" do
      structure = [
        child(:source, StaticPads.Source)
        |> child(:sink, StaticPads.Sink),
        get_child(:source)
        |> get_child(:sink)
      ]

      {:error, {{%Membrane.LinkError{}, _stackstrace}, _meta}} =
        Pipeline.start_supervised(structure: structure)
    end

    test "dynamic pads" do
      structure = [
        child(:source, DynamicPads.Source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:sink, StaticPads.Sink),
        get_child(:source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:sink)
      ]

      {:error, {{%Membrane.LinkError{}, _stackstrace}, _meta}} =
        Pipeline.start_supervised(structure: structure)
    end
  end

  describe "returning a spec with links to already used" do
    test "static pads" do
      structure = [
        child(:source, StaticPads.Source) |> child(:sink, StaticPads.Sink)
      ]

      pipeline = Pipeline.start_supervised!(structure: structure)
      ref = Process.monitor(pipeline)

      spec = %Membrane.ChildrenSpec{
        structure: [
          get_child(:source) |> get_child(:sink)
        ]
      }

      Pipeline.execute_actions(pipeline, spec: spec)

      assert_receive({:DOWN, ^ref, :process, ^pipeline, {%Membrane.LinkError{}, _stacktrace}})
    end

    test "dynamic pads" do
      structure = [
        child(:source, DynamicPads.Source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:sink, DynamicPads.Sink)
      ]

      pipeline = Pipeline.start_supervised!(structure: structure)
      ref = Process.monitor(pipeline)

      spec = %Membrane.ChildrenSpec{
        structure: [
          get_child(:source)
          |> via_out(Pad.ref(:output, 1))
          |> via_in(Pad.ref(:input, 1))
          |> get_child(:sink)
        ]
      }

      Pipeline.execute_actions(pipeline, spec: spec)

      assert_receive({:DOWN, ^ref, :process, ^pipeline, {%Membrane.LinkError{}, _stacktrace}})
    end
  end
end
