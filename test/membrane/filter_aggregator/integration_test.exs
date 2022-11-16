defmodule Membrane.FilterAggregator.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.FilterAggregator
  alias Membrane.RemoteStream
  alias Membrane.Testing.{Pipeline, Sink, Source}

  defmodule FilterA do
    use Membrane.Filter

    def_input_pad :input, demand_unit: :buffers, demand_mode: :auto, accepted_format: RemoteStream
    def_output_pad :output, demand_mode: :auto, accepted_format: RemoteStream

    @impl true
    def handle_process(:input, %Buffer{payload: <<idx, payload::binary>>}, _ctx, state) do
      payload = for <<i <- payload>>, into: <<>>, do: <<i - 2>>
      {[buffer: {:output, %Buffer{payload: <<idx, payload::binary>>}}], state}
    end
  end

  defmodule FilterB do
    use Membrane.Filter

    def_input_pad :input, demand_unit: :buffers, demand_mode: :auto, accepted_format: RemoteStream
    def_output_pad :output, demand_mode: :auto, accepted_format: RemoteStream

    @impl true
    def handle_process_list(:input, buffers, _ctx, state) do
      buffers =
        buffers
        |> Enum.map(fn %Buffer{payload: <<idx, payload::binary>>} ->
          payload = for <<i <- payload>>, into: <<>>, do: <<i - 1>>
          %Buffer{payload: <<idx, payload::binary>>}
        end)

      {[buffer: {:output, buffers}], state}
    end
  end

  test "pipeline with 2 filters" do
    payload = for i <- 3..256, into: <<>>, do: <<i>>
    buffers_num_range = 1..100
    output = for i <- buffers_num_range, do: <<i, payload::binary>>

    links = [
      child(:src, %Source{output: output})
      |> child(:filters, %FilterAggregator{
        filters: [
          a: FilterA,
          b: FilterB
        ]
      })
      |> child(:sink, Sink)
    ]

    pid = Pipeline.start_link_supervised!(structure: links)
    assert_start_of_stream(pid, :sink)
    assert_sink_stream_format(pid, :sink, %RemoteStream{})

    expected_payload = for i <- 0..253, into: <<>>, do: <<i>>

    for i <- buffers_num_range do
      assert_sink_buffer(pid, :sink, %Membrane.Buffer{payload: <<^i, ^expected_payload::binary>>})
    end

    assert_end_of_stream(pid, :sink)
  end
end
