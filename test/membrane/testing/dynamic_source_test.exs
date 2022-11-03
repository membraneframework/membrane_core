defmodule Membrane.Testing.DynamicSourceTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
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

  test "Source sends stream format on play" do
    assert {{:ok, stream_format: {:output, :stream_format}}, _state} =
             Testing.DynamicSource.handle_playing(%{pads: %{:output => %{}}}, %{
               stream_format: :stream_format
             })
  end

  test "Source works properly when payload are passed as enumerable" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        structure:
          [
            child(:source, %Testing.DynamicSource{output: ['a', 'b', 'c']}),
            child(:sink_1, Testing.Sink),
            child(:sink_2, Testing.Sink)
          ] ++
            [
              get_child(:source) |> get_child(:sink_1),
              get_child(:source) |> get_child(:sink_2)
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
        structure:
          [
            child(:source, Testing.DynamicSource),
            child(:sink_1, Testing.Sink),
            child(:sink_2, Testing.Sink)
          ] ++
            [
              get_child(:source) |> get_child(:sink_1),
              get_child(:source) |> get_child(:sink_2)
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
