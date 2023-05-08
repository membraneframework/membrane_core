defmodule Membrane.Integration.SimpleElementsTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Simple
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

  test "Membrane.Simple.Filter maps buffers with function passed in :handle_buffer option" do
    payload_suffix = "payload suffix"

    buffer_mapper = fn %Buffer{} = buffer ->
      Map.update!(buffer, :payload, &(&1 <> payload_suffix))
    end

    spec =
      child(:source, HelperSource)
      |> child(%Simple.Filter{handle_buffer: buffer_mapper})
      |> child(:sink, Testing.Sink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_stream_format(pipeline, :sink, _any)

    Testing.Pipeline.message_child(pipeline, :source, {:send_buffers, 100})

    for i <- 1..100 do
      expected_payload = inspect(i) <> payload_suffix
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^expected_payload})
    end

    Testing.Pipeline.terminate(pipeline)
  end

  test "Membrane.Simple.Sink calls function passed in :handle_buffer" do
    test_pid = self()

    spec =
      child(:source, HelperSource)
      |> child(:sink, %Simple.Sink{
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
