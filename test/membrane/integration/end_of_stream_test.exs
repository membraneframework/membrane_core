defmodule Membrane.EndOfStreamTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule EOSSource do
    use Membrane.Source

    def_output_pad :output, flow_control: :push, accepted_format: _any

    @impl true
    def handle_playing(_ctx, state) do
      {[end_of_stream: :output], state}
    end
  end

  defmodule EOSSink do
    use Membrane.Sink

    def_input_pad :input, flow_control: :push, accepted_format: _any

    @impl true
    def handle_start_of_stream(_pad, _ctx, _state) do
      raise "This callback shouldn't be invoked"
    end

    @impl true
    def handle_end_of_stream(:input, %{preceded_by_start_of_stream?: false}, state) do
      {[], state}
    end
  end

  test "send end of stream without start of stream" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:source, EOSSource)
          |> child(:sink, EOSSink)
      )

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.terminate(pipeline)
  end
end
