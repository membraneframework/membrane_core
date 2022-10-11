defmodule Membrane.CapsTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Support.CapsTest
  alias Membrane.Testing.Pipeline

  setup do
    children = [
      source: CapsTest.Source,
      bin: %CapsTest.Bin{test_pid: self()}
    ]

    pipeline = Pipeline.start_link_supervised!(links: Membrane.ParentSpec.link_linear(children))

    [pipeline: pipeline]
  end

  test "Caps should be accepted, when they match caps spec in bin", %{pipeline: pipeline} do
    format = CapsTest.Bin.accepted_format()
    caps = %CapsTest.Stream{format: format}
    Pipeline.execute_actions(pipeline, notify_child: {:source, {:send_caps, caps}})

    assert_pipeline_notified(pipeline, :bin, {:caps_received, ^caps})
  end

  test "Error should be raised, when caps don't match caps spec in bin", %{pipeline: pipeline} do
    format = CapsTest.Bin.unaccepted_format()
    caps = %CapsTest.Stream{format: format}

    sink_pid =
      receive do
        {:sink_pid, sink_pid} ->
          Process.monitor(sink_pid)
          sink_pid
      after
        2000 ->
          raise "Sink hasn't sent its pid before timeout"
      end

    Pipeline.execute_actions(pipeline, notify_child: {:source, {:send_caps, caps}})

    assert_receive({:DOWN, _ref, :process, ^sink_pid, _error})
  end
end
