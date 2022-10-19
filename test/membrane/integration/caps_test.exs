defmodule Membrane.CapsTest do
  use ExUnit.Case

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
      pipeline = caps_test_pipeline(Source, OuterSinkBin)
      send_caps(pipeline, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end

    test "output caps patterns in bins" do
      pipeline = caps_test_pipeline(OuterSourceBin, Sink)
      send_caps(pipeline, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end
  end

  describe "Error should be raised, when caps don't match" do
    test "input caps patterns in element" do
      pipeline = caps_test_pipeline(Source, RestrictiveSink)
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_down(RestrictiveSink)
    end

    test "input caps patterns in inner bin" do
      pipeline = caps_test_pipeline(Source, OuterSinkBin)
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_down(Sink)
    end

    test "input caps patterns in outer bin" do
      pipeline = caps_test_pipeline(Source, OuterSinkBin)
      send_caps(pipeline, FormatAcceptedByInnerBins)
      assert_down(Sink)
    end

    test "output caps patterns in element" do
      pipeline = caps_test_pipeline(RestrictiveSource, Sink)
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_down(RestrictiveSource)
    end

    test "output caps patterns in inner bin" do
      pipeline = caps_test_pipeline(OuterSourceBin, Sink)
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_down(Source)
    end

    test "output caps patterns in outer bin" do
      pipeline = caps_test_pipeline(OuterSourceBin, Sink)
      send_caps(pipeline, FormatAcceptedByInnerBins)
      assert_down(Source)
    end
  end

  defp caps_test_pipeline(source, sink) do
    structure =
      Membrane.ChildrenSpec.link_linear(
        source: struct!(source, test_pid: self()),
        sink: struct!(sink, test_pid: self())
      )

    Pipeline.start_supervised!(structure: structure)
  end

  defp send_caps(pipeline, caps_format) do
    caps = %CapsTest.Stream{format: caps_format}
    Pipeline.execute_actions(pipeline, notify_child: {:source, {:send_caps, caps}})
  end

  defp assert_down(module) do
    assert_receive({:my_pid, ^module, pid})
    Process.monitor(pid)
    assert_receive({:DOWN, _ref, :process, ^pid, {%Membrane.CapsMatchError{}, _stacktrace}})
  end
end
