defmodule Membrane.CapsTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.CapsTest

  alias Membrane.Support.CapsTest.{
    OuterSinkBin,
    OuterSourceBin,
    RestrictiveSink,
    RestrictiveSource,
    Sink,
    Source
  }

  alias Membrane.Support.CapsTest.Stream.{
    FormatAcceptedByAll,
    FormatAcceptedByInnerBins,
    FormatAcceptedByOuterBins
  }

  alias Membrane.Testing.Pipeline

  describe "Caps should be accepted, when they match" do
    test "input caps patterns in bins" do
      pipeline = start_test_pipeline(Source, OuterSinkBin, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end

    test "output caps patterns in bins" do
      pipeline = start_test_pipeline(OuterSourceBin, Sink, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end
  end

  describe "Error should be raised, when caps don't match" do
    test "input caps patterns in element" do
      start_test_pipeline(Source, RestrictiveSink, FormatAcceptedByOuterBins)
      assert_down(RestrictiveSink)
    end

    test "input caps patterns in inner bin" do
      start_test_pipeline(Source, OuterSinkBin, FormatAcceptedByOuterBins)
      assert_down(Sink)
    end

    test "input caps patterns in outer bin" do
      start_test_pipeline(Source, OuterSinkBin, FormatAcceptedByInnerBins)
      assert_down(Sink)
    end

    test "output caps patterns in element" do
      start_test_pipeline(RestrictiveSource, Sink, FormatAcceptedByOuterBins)
      assert_down(RestrictiveSource)
    end

    test "output caps patterns in inner bin" do
      start_test_pipeline(OuterSourceBin, Sink, FormatAcceptedByOuterBins)
      assert_down(Source)
    end

    test "output caps patterns in outer bin" do
      start_test_pipeline(OuterSourceBin, Sink, FormatAcceptedByInnerBins)
      assert_down(Source)
    end
  end

  defp start_test_pipeline(source, sink, caps_format) do
    caps = %CapsTest.Stream{format: caps_format}
    source_struct = struct!(source, test_pid: self(), caps: caps)
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
    assert_receive({:DOWN, _ref, :process, ^pid, {%Membrane.CapsError{}, _stacktrace}})
  end
end
