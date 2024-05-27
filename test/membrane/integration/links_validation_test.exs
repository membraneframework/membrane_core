defmodule Membrane.LinksValidationTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.Pad
  alias Membrane.Testing.Pipeline

  require Membrane.Pad

  defmodule StreamFormat do
    defstruct []
  end

  defmodule StaticPads do
    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input,
        accepted_format: _any,
        availability: :always,
        flow_control: :push
    end

    defmodule Source do
      use Membrane.Source

      def_output_pad :output,
        accepted_format: _any,
        availability: :always,
        flow_control: :push

      @impl true
      def handle_playing(_ctx, state) do
        stream_format = %Membrane.LinksValidationTest.StreamFormat{}
        {[stream_format: {:output, stream_format}], state}
      end
    end
  end

  defmodule DynamicPads do
    defmodule Sink do
      use Membrane.Sink

      def_input_pad :input,
        accepted_format: _any,
        availability: :on_request,
        flow_control: :push
    end

    defmodule Source do
      use Membrane.Source

      def_output_pad :output,
        accepted_format: _any,
        availability: :on_request,
        flow_control: :push

      @impl true
      def handle_playing(_ctx, state) do
        stream_format = %Membrane.LinksValidationTest.StreamFormat{}
        {[stream_format: {:output, stream_format}], state}
      end
    end
  end

  describe "returning a spec with many links to this same" do
    test "static pads" do
      spec = [
        child(:source, StaticPads.Source)
        |> child(:sink, StaticPads.Sink),
        get_child(:source)
        |> get_child(:sink)
      ]

      {:error, {{%Membrane.LinkError{}, _stackstrace}, _meta}} =
        Pipeline.start_supervised(spec: [spec, spec])
    end

    test "dynamic pads" do
      spec = [
        child(:source, DynamicPads.Source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:sink, DynamicPads.Sink),
        get_child(:source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:sink)
      ]

      {:error, {{%Membrane.LinkError{}, _stackstrace}, _meta}} =
        Pipeline.start_supervised(spec: spec)
    end
  end

  describe "returning a spec with links to already used" do
    test "static pads" do
      spec = child(:source, StaticPads.Source) |> child(:sink, StaticPads.Sink)

      pipeline = Pipeline.start_supervised!(spec: spec)
      ref = Process.monitor(pipeline)

      spec = get_child(:source) |> get_child(:sink)

      Pipeline.execute_actions(pipeline, spec: spec)

      assert_receive({:DOWN, ^ref, :process, ^pipeline, {%Membrane.LinkError{}, _stacktrace}})
    end

    test "dynamic pads" do
      spec =
        child(:source, DynamicPads.Source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> child(:sink, DynamicPads.Sink)

      pipeline = Pipeline.start_supervised!(spec: spec)
      ref = Process.monitor(pipeline)

      spec =
        get_child(:source)
        |> via_out(Pad.ref(:output, 1))
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:sink)

      Pipeline.execute_actions(pipeline, spec: spec)

      assert_receive {:DOWN, ^ref, :process, ^pipeline, {%Membrane.LinkError{}, _stacktrace}},
                     1000
    end
  end
end
