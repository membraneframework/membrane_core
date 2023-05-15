defmodule Membrane.Integration.DebugElementsTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Debug
  alias Membrane.Testing

  test "Membrane.Debug.Filter calls function passed in :handle_buffer and forwards buffers on :output pad" do
    payloads = Enum.map(1..100, &inspect/1)
    test_pid = self()

    spec =
      child(:source, %Testing.Source{output: payloads})
      |> child(%Debug.Filter{handle_buffer: &send(test_pid, {:buffer, &1})})
      |> child(:sink, Testing.Sink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_stream_format(pipeline, :sink, _any)

    for expected_payload <- payloads do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^expected_payload})
      assert_receive {:buffer, %Buffer{payload: ^expected_payload}}
    end

    Testing.Pipeline.terminate(pipeline)
  end

  test "Membrane.Debug.Sink calls function passed in :handle_buffer" do
    payloads = Enum.map(1..100, &inspect/1)
    test_pid = self()

    spec =
      child(:source, %Testing.Source{output: payloads})
      |> child(:sink, %Debug.Sink{
        handle_buffer: &send(test_pid, {:buffer, &1}),
        handle_stream_format: &send(test_pid, {:stream_format, &1})
      })

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_receive {:stream_format, _any}

    for expected_payload <- payloads do
      assert_receive {:buffer, %Buffer{payload: ^expected_payload}}
    end

    Testing.Pipeline.terminate(pipeline)
  end
end
