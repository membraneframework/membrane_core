defmodule Membrane.Testing.DynamicSourceTest do
  use ExUnit.Case

  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing

  test "Source initializes buffer generator and its state properly" do
    generator = fn _state, _size -> nil end

    assert {:ok,
            %{type: :generator, generator: ^generator, generator_state: :abc, state_for_pad: %{}}} =
             Testing.DynamicSource.handle_init(%{}, %Testing.DynamicSource{
               output: {:abc, generator}
             })
  end

  test "Source sends caps on play" do
    assert {{:ok, caps: {:output, :caps}}, _state} =
             Testing.DynamicSource.handle_playing(%{pads: %{:output => %{}}}, %{
               caps: :caps
             })
  end

  test "Source works properly when payload are passed as enumerable" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        children: [
          source: %Testing.DynamicSource{output: ['a', 'b', 'c']},
          sink_1: Testing.Sink,
          sink_2: Testing.Sink
        ],
        links: [
          link(:source) |> to(:sink_1),
          link(:source) |> to(:sink_2)
        ]
      )

    assert_pipeline_play(pipeline)
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: 'a'})
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: 'b'})
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: 'c'})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: 'a'})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: 'b'})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: 'c'})
  end

  test "Source works properly when using generator function" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        children: [
          source: Testing.DynamicSource,
          sink_1: Testing.Sink,
          sink_2: Testing.Sink
        ],
        links: [
          link(:source) |> to(:sink_1),
          link(:source) |> to(:sink_2)
        ]
      )

    assert_pipeline_play(pipeline)
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: <<0::16>>})
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: <<1::16>>})
    assert_sink_buffer(pipeline, :sink_1, %Buffer{payload: <<2::16>>})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: <<0::16>>})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: <<1::16>>})
    assert_sink_buffer(pipeline, :sink_2, %Buffer{payload: <<2::16>>})
  end
end
