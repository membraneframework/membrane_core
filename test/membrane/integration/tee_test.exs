defmodule Membrane.Integration.TeeTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use Bunch

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing.{Pipeline, Sink, Source}

  test "forwards input to three all outputs" do
    range = 1..100
    sinks = [:sink1, :sink2, :sink3, :sink_4]

    spec =
      [
        child(:src, %Source{output: range})
        |> child(:tee, Membrane.Tee)
      ] ++
        for sink <- sinks do
          pad = if sink in [:sink1, :sink2], do: :output, else: :output_copy

          get_child(:tee)
          |> via_out(pad)
          |> child(sink, %Sink{})
        end

    pipeline = Pipeline.start_link_supervised!(spec: spec)

    for sink <- sinks do
      assert_end_of_stream(pipeline, ^sink, :input)
    end

    for element <- range, sink <- sinks do
      assert_sink_buffer(pipeline, sink, %Buffer{payload: ^element})
    end

    for {pad, sink} <- [output_copy: :sink5, output: :sink6] do
      spec =
        get_child(:tee)
        |> via_out(pad)
        |> child(sink, %Sink{})

      Pipeline.execute_actions(pipeline, spec: spec)
    end

    for sink <- [:sink5, :sink6] do
      assert_sink_stream_format(pipeline, sink, %Membrane.RemoteStream{})
      assert_end_of_stream(pipeline, ^sink, :input)
    end

    Pipeline.terminate(pipeline)
  end
end
