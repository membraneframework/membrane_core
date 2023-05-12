defmodule Membrane.Integration.DebugElementsTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Debug
  alias Membrane.Testing

  defmodule HelperSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :push, accepted_format: _any

    defmodule StreamFormat do
      defstruct []
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[stream_format: {:output, %StreamFormat{}}], state}
    end

    @impl true
    def handle_parent_notification({:send_buffers, number}, _ctx, state) do
      buffers =
        Enum.map(1..number, fn i ->
          %Buffer{payload: inspect(i)}
        end)

      {[buffer: {:output, buffers}], state}
    end
  end

  test "Membrane.Debug.Filter calls function passed in :handle_buffer and forwards buffers on :output pad" do
    test_pid = self()

    spec =
      child(:source, HelperSource)
      |> child(%Debug.Filter{handle_buffer: &send(test_pid, {:buffer, &1})})
      |> child(:sink, Testing.Sink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_stream_format(pipeline, :sink, _any)

    Testing.Pipeline.message_child(pipeline, :source, {:send_buffers, 100})

    for i <- 1..100 do
      expected_payload = inspect(i)
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^expected_payload})
      assert_receive {:buffer, %Buffer{payload: ^expected_payload}}
    end

    Testing.Pipeline.terminate(pipeline)
  end

  test "Membrane.Debug.Sink calls function passed in :handle_buffer" do
    test_pid = self()

    spec =
      child(:source, HelperSource)
      |> child(:sink, %Debug.Sink{
        handle_buffer: &send(test_pid, {:buffer, &1}),
        handle_stream_format: &send(test_pid, {:stream_format, &1})
      })

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_receive {:stream_format, _any}

    Testing.Pipeline.message_child(pipeline, :source, {:send_buffers, 100})

    for i <- 1..100 do
      expected_payload = inspect(i)
      assert_receive {:buffer, %Buffer{payload: ^expected_payload}}
    end

    Testing.Pipeline.terminate(pipeline)
  end
end
