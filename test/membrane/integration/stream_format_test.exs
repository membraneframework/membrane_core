defmodule Membrane.StreamFormatTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.AcceptedFormatTest.{
    OuterSinkBin,
    OuterSourceBin,
    RestrictiveSink,
    RestrictiveSource,
    Sink,
    Source,
    StreamFormat
  }

  alias Membrane.Support.AcceptedFormatTest.StreamFormat.{
    AcceptedByAll,
    AcceptedByInnerBins,
    AcceptedByOuterBins
  }

  alias Membrane.Testing.Pipeline

  describe "Stream format should be accepted, when they match" do
    test "input pad :accepted_format in bins" do
      pipeline = start_test_pipeline(Source, OuterSinkBin, AcceptedByAll)
      assert_strean_format_accepted(pipeline, Source, AcceptedByAll)
    end

    test "output pad :accepted_format in bins" do
      pipeline = start_test_pipeline(OuterSourceBin, Sink, AcceptedByAll)
      assert_strean_format_accepted(pipeline, Source, AcceptedByAll)
    end
  end

  describe "Error should be raised, when stream format don't match" do
    test "input pad :accepted_format in element" do
      start_test_pipeline(Source, RestrictiveSink, AcceptedByOuterBins)
      assert_down(RestrictiveSink, source_module: Source)
    end

    test "input pad :accepted_format in inner bin" do
      start_test_pipeline(Source, OuterSinkBin, AcceptedByOuterBins)
      assert_down(Sink, source_module: Source)
    end

    @tag :dupa
    test "input pad :accepted_format in outer bin" do
      start_test_pipeline(Source, OuterSinkBin, AcceptedByInnerBins)
      assert_down(Sink, source_module: Source)
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

    spec = child(:source, source_struct) |> child(:sink, sink_struct)

    Pipeline.start_supervised!(spec: spec)
  end

  defp assert_down(module, source_module: source_module) do
    {source_pid, monitor_pid} =
      if module == source_module do
        assert_receive({:my_pid, ^module, pid})
        {pid, pid}
      else
        assert_receive({:my_pid, ^source_module, source_pid})
        assert_receive({:my_pid, ^module, monitor_pid})
        {source_pid, monitor_pid}
      end

    monitor_ref = Process.monitor(monitor_pid)
    send(source_pid, :send_stream_format)

    assert_receive({:DOWN, ^monitor_ref, :process, _pid, {%Membrane.StreamFormatError{}, _stacktrace}})
  end

  defp assert_down(module) do
    assert_down(module, source_module: module)
  end

  defp assert_strean_format_accepted(pipeline, source_module, stream_format_format) do
    assert_receive({:my_pid, ^source_module, pid})
    send(pid, :send_stream_format)

    assert_pipeline_notified(
      pipeline,
      :sink,
      {:stream_format_received, %StreamFormat{format: ^stream_format_format}}
    )
  end
end
