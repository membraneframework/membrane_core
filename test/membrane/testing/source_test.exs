defmodule Membrane.Testing.SourceTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing.Pipeline
  alias Membrane.Testing.Sink
  alias Membrane.Testing.Source

  test "Source initializes buffer generator and its state properly" do
    generator = fn _state, _size -> nil end

    assert {[], %{output: ^generator, generator_state: :abc}} =
             Source.handle_init(%{}, %Source{output: {:abc, generator}})
  end

  test "Source sends stream format on play" do
    assert {[stream_format: {:output, :stream_format}], _state} =
             Source.handle_playing(nil, %{stream_format: :stream_format})
  end

  describe "Source when handling demand" do
    test "sends next buffer if :output is an enumerable" do
      payloads = Enum.into(1..10, [])
      demand_size = 3

      assert {actions, state} =
               Source.handle_demand(:output, demand_size, :buffers, nil, %{
                 output: payloads,
                 all_buffers_in_output?: false
               })

      assert [{:buffer, {:output, buffers}}] = actions

      buffers
      |> Enum.zip(1..demand_size)
      |> Enum.each(fn {%Buffer{payload: payload}, num} -> assert num == payload end)

      assert List.first(state.output) == demand_size + 1
      assert Enum.count(state.output) + demand_size == Enum.count(payloads)
    end

    test "sends end of stream if :output enumerable is empty (split returned [])" do
      payload = 1
      payloads = [payload]

      assert {actions, _state} =
               Source.handle_demand(:output, 2, :buffers, nil, %{
                 output: payloads,
                 all_buffers_in_output?: false
               })

      assert [
               {:buffer, {:output, [buffer]}},
               {:end_of_stream, :output}
             ] = actions

      assert %Buffer{payload: payload} == buffer
    end
  end

  test "Created generator function sends end_of_stream if leftover is empty" do
    buffers = [%Membrane.Buffer{payload: 1}]
    assert {state, generator} = Source.output_from_buffers(buffers)

    assert {actions, _state} =
             Source.handle_demand(:output, 2, :buffers, nil, %{
               generator_state: state,
               output: generator
             })

    assert [
             {:buffer, {:output, [buffer]}},
             {:end_of_stream, :output}
           ] = actions

    assert %Buffer{payload: 1} == buffer
  end

  test "Source wraps the elements of `Enum.t()` into `Membrane.Buffer.t()` if any of these elements is not a `Membrane.Buffer.t()`" do
    pipeline = Pipeline.start_supervised!()
    output = [%Buffer{payload: 1}, 2, 3]
    spec = child(:source, %Source{output: output}) |> child(:sink, Sink)
    Pipeline.execute_actions(pipeline, spec: spec)

    result_buffers = Enum.map(output, &%Buffer{payload: &1})
    Enum.each(result_buffers, &assert_sink_buffer(pipeline, :sink, ^&1))
  end

  test "Source doesn't wrap the elements of `Enum.t()` into `Membrane.Buffer.t()` if all of these elements are `Membrane.Buffer.t()`" do
    pipeline = Pipeline.start_supervised!()
    output = [%Buffer{payload: 1}, %Buffer{payload: 2}, %Buffer{payload: 3}]
    spec = child(:source, %Source{output: output}) |> child(:sink, Sink)
    Pipeline.execute_actions(pipeline, spec: spec)

    result_buffers = output
    Enum.each(result_buffers, &assert_sink_buffer(pipeline, :sink, ^&1))
  end
end
