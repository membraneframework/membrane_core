# defmodule Membrane.FilterAggregator.IntegrationTest do
#   use ExUnit.Case, async: true

#   import Membrane.Testing.Assertions

#   alias Membrane.Buffer
#   alias Membrane.FilterAggregator
#   alias Membrane.ChildrenSpec
#   alias Membrane.RemoteStream
#   alias Membrane.Testing.{Pipeline, Sink, Source}

#   defmodule FilterA do
#     use Membrane.Filter

#     def_input_pad :input, demand_unit: :buffers, demand_mode: :auto, caps: RemoteStream
#     def_output_pad :output, demand_mode: :auto, caps: RemoteStream

#     @impl true
#     def handle_process(:input, %Buffer{payload: <<idx, payload::binary>>}, _ctx, state) do
#       payload = for <<i <- payload>>, into: <<>>, do: <<i - 2>>
#       {{:ok, buffer: {:output, %Buffer{payload: <<idx, payload::binary>>}}}, state}
#     end
#   end

#   defmodule FilterB do
#     use Membrane.Filter

#     def_input_pad :input, demand_unit: :buffers, demand_mode: :auto, caps: RemoteStream
#     def_output_pad :output, demand_mode: :auto, caps: RemoteStream

#     @impl true
#     def handle_process_list(:input, buffers, _ctx, state) do
#       buffers =
#         buffers
#         |> Enum.map(fn %Buffer{payload: <<idx, payload::binary>>} ->
#           payload = for <<i <- payload>>, into: <<>>, do: <<i - 1>>
#           %Buffer{payload: <<idx, payload::binary>>}
#         end)

#       {{:ok, buffer: {:output, buffers}}, state}
#     end
#   end

#   test "pipeline with 2 filters" do
#     payload = for i <- 3..256, into: <<>>, do: <<i>>
#     buffers_num_range = 1..100
#     output = for i <- buffers_num_range, do: <<i, payload::binary>>

#     links =
#       [
#         src: %Source{output: output},
#         filters: %FilterAggregator{
#           filters: [
#             a: FilterA,
#             b: FilterB
#           ]
#         },
#         sink: Sink
#       ]
#       |> ChildrenSpec.link_linear()

#     pid = Pipeline.start_link_supervised!(links: links)
#     assert_start_of_stream(pid, :sink)
#     assert_sink_caps(pid, :sink, %RemoteStream{})

#     expected_payload = for i <- 0..253, into: <<>>, do: <<i>>

#     for i <- buffers_num_range do
#       assert_sink_buffer(pid, :sink, %Membrane.Buffer{payload: <<^i, ^expected_payload::binary>>})
#     end

#     assert_end_of_stream(pid, :sink)
#   end
# end
