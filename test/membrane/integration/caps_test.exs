defmodule Membrane.CapsTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Support.CapsTest

  alias Membrane.Support.CapsTest.Stream.{
    FormatAcceptedByAll,
    FormatAcceptedByInnerBins,
    FormatAcceptedByOuterBins
  }

  alias Membrane.Testing.Pipeline

  describe "Caps should be accepted, when they match" do
    test "input caps patterns in bins" do
      pipeline = pipeline_with_sink_bins()
      send_caps(pipeline, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end

    test "output caps patterns in bins" do
      pipeline = pipeline_with_source_bins()
      send_caps(pipeline, FormatAcceptedByAll)

      assert_pipeline_notified(
        pipeline,
        :sink,
        {:caps_received, %CapsTest.Stream{format: FormatAcceptedByAll}}
      )
    end
  end

  describe "Error should be raised, when caps don't match" do
    test "input caps patterns in inner bins" do
      pipeline = pipeline_with_sink_bins()
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_sink_down()
    end

    test "input caps patterns in outer bins" do
      pipeline = pipeline_with_sink_bins()
      send_caps(pipeline, FormatAcceptedByInnerBins)
      assert_sink_down()
    end

    test "output caps patterns in inner bins" do
      pipeline = pipeline_with_source_bins()
      send_caps(pipeline, FormatAcceptedByOuterBins)
      assert_source_down()
    end

    test "output caps patterns in outer bins" do
      pipeline = pipeline_with_source_bins()
      send_caps(pipeline, FormatAcceptedByInnerBins)
      assert_source_down()
    end
  end

  defp pipeline_with_sink_bins() do
    structure =
      Membrane.ChildrenSpec.link_linear(
        source: %CapsTest.Source{test_pid: self()},
        sink: %CapsTest.OuterSinkBin{test_pid: self()}
      )

    Pipeline.start_link_supervised!(structure: structure)
  end

  defp pipeline_with_source_bins() do
    structure =
      Membrane.ChildrenSpec.link_linear(
        source: %CapsTest.OuterSourceBin{test_pid: self()},
        sink: %CapsTest.Sink{test_pid: self()}
      )

    Pipeline.start_link_supervised!(structure: structure)
  end

  defp send_caps(pipeline, caps_format) do
    caps = %CapsTest.Stream{format: caps_format}
    Pipeline.execute_actions(pipeline, notify_child: {:source, {:send_caps, caps}})
  end

  defp assert_source_down() do
    source_pid =
      receive do
        {:source_pid, source_pid} ->
          Process.monitor(source_pid)
          source_pid
      after
        2000 ->
          raise "Source hasn't sent its pid before timeout"
      end

    assert_receive({:DOWN, _ref, :process, ^source_pid, {%Membrane.ElementError{}, _stacktrace}})
  end

  defp assert_sink_down() do
    sink_pid =
      receive do
        {:sink_pid, sink_pid} ->
          Process.monitor(sink_pid)
          sink_pid
      after
        2000 ->
          raise "Sink hasn't sent its pid before timeout"
      end

    assert_receive({:DOWN, _ref, :process, ^sink_pid, {%Membrane.ElementError{}, _stacktrace}})
  end
end
