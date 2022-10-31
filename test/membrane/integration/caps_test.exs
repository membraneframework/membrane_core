defmodule Membrane.StreamFormatTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.StreamFormatTest.{
    OuterSinkBin,
    OuterSourceBin,
    RestrictiveSink,
    RestrictiveSource,
    Sink,
    Source,
    StreamFormat
  }

  alias Membrane.Support.StreamFormatTest.StreamFormat.{
    AcceptedByAll,
    AcceptedByInnerBins,
    AcceptedByOuterBins
  }

  alias Membrane.Testing.Pipeline

  describe "Stream format should be accepted, when they match" do
    test "input pad :accepted_format in bins" do
      pipeline = start_test_pipeline(Source, OuterSinkBin, AcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:stream_format_received, %StreamFormat{format: AcceptedByAll}}
      )
    end

    test "output pad :accepted_format in bins" do
      pipeline = start_test_pipeline(OuterSourceBin, Sink, AcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:stream_format_received, %StreamFormat{format: AcceptedByAll}}
      )
    end
  end

  describe "Error should be raised, when stream format don't match" do
    test "input pad :accepted_format in element" do
      start_test_pipeline(Source, RestrictiveSink, AcceptedByOuterBins)
      assert_down(RestrictiveSink)
    end

    test "input pad :accepted_format in inner bin" do
      start_test_pipeline(Source, OuterSinkBin, AcceptedByOuterBins)
      assert_down(Sink)
    end

    test "input pad :accepted_format in outer bin" do
      start_test_pipeline(Source, OuterSinkBin, AcceptedByInnerBins)
      assert_down(Sink)
    end

    test "output pad :accepted_format in element" do
      start_test_pipeline(RestrictiveSource, Sink, AcceptedByOuterBins)
      assert_down(RestrictiveSource)
    end

    test "output pad :accepted_format in inner bin" do
      start_test_pipeline(OuterSourceBin, Sink, AcceptedByOuterBins)
      assert_down(Source)
    end

    test "output pad :accepted_format in outer bin" do
      start_test_pipeline(OuterSourceBin, Sink, AcceptedByInnerBins)
      assert_down(Source)
    end
  end

  defp start_test_pipeline(source, sink, stream_format_format) do
    stream_format = %StreamFormat{format: stream_format_format}
    source_struct = struct!(source, test_pid: self(), stream_format: stream_format)
    sink_struct = struct!(sink, test_pid: self())

    structure = [
      child(:source, source_struct)
      |> child(:sink, sink_struct)
    ]

    Pipeline.start_supervised!(structure: structure)
  end

  defp assert_down(module) do
    assert_receive({:my_pid, ^module, pid})
    Process.monitor(pid)
    assert_receive({:DOWN, _ref, :process, ^pid, {%Membrane.StreamFormatError{}, _stacktrace}})
  end
end
