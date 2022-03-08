defmodule Membrane.FailWhenNoCapsAreSent do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  alias Membrane.Testing.{Source, Sink, Pipeline}

  defmodule SourceWhichDoesNotSendCaps do
    use Membrane.Source

    def_output_pad(:output, caps: :any, mode: :pull)

    @impl true
    def handle_init(_options) do
      {:ok, %{}}
    end

    @impl true
    def handle_demand(:output, _size, :buffers, _ctx, state) do
      {{:ok, [buffer: {:output, %Membrane.Buffer{payload: "Something"}}]}, state}
    end
  end

  test "if pipeline crashes when the caps are not sent before the first buffer" do
    options = %Pipeline.Options{
      elements: [
        source: SourceWhichDoesNotSendCaps,
        sink: Sink
      ]
    }
    {:ok, pipeline} = Pipeline.start(options)
    ref = Process.monitor(pipeline)
    Pipeline.play(pipeline)
    assert_receive {:DOWN, ^ref, :process, ^pipeline, {:shutdown, :child_crash}}
  end

  test "if pipeline works properly when caps are sent before the first buffer" do
    options = %Pipeline.Options{
      elements: [
        source: Source,
        sink: Sink
      ]
    }
    {:ok, pipeline} = Pipeline.start(options)
    ref = Process.monitor(pipeline)
    Pipeline.play(pipeline)
    assert_start_of_stream(pipeline, :sink)
    refute_receive {:DOWN, ^ref, :process, ^pipeline, {:shutdown, :child_crash}}
    Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

end
