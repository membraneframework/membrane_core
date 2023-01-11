defmodule Membrane.Testing.EndpointTest do
  use ExUnit.Case

  alias Membrane.Buffer
  alias Membrane.Testing.{Endpoint, Notification}

  test "Endpoint initializes buffer generator and its state properly" do
    generator = fn _state, _size -> nil end

    assert {[], %{output: ^generator, generator_state: :abc}} =
             Endpoint.handle_init(%{}, %Endpoint{output: {:abc, generator}})
  end

  test "Endpoint sends stream format on play" do
    assert {[stream_format: {:output, :stream_format}], _state} =
             Endpoint.handle_playing(nil, %{stream_format: :stream_format})
  end

  describe "Handle buffer" do
    test "demands when autodemand is true" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {actions, _state} = Endpoint.handle_buffer(:input, buffer, nil, %{autodemand: true})

      assert actions == [
               demand: :input,
               notify_parent: %Notification{payload: {:buffer, buffer}}
             ]
    end

    test "does not demand when autodemand is false" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {actions, _state} = Endpoint.handle_buffer(:input, buffer, nil, %{autodemand: false})

      assert actions == [notify_parent: %Notification{payload: {:buffer, buffer}}]
    end
  end

  describe "Endpoint when handling demand" do
    test "sends next buffer if :output is an enumerable" do
      payloads = Enum.into(1..10, [])
      demand_size = 3

      assert {actions, state} =
               Endpoint.handle_demand(:output, demand_size, :buffers, nil, %{output: payloads})

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
               Endpoint.handle_demand(:output, 2, :buffers, nil, %{output: payloads})

      assert [
               {:buffer, {:output, [buffer]}},
               {:end_of_stream, :output}
             ] = actions

      assert %Buffer{payload: payload} == buffer
    end
  end

  test "Created generator function sends end_of_stream if leftover is empty" do
    buffers = [%Membrane.Buffer{payload: 1}]
    assert {state, generator} = Endpoint.output_from_buffers(buffers)

    assert {actions, _state} =
             Endpoint.handle_demand(:output, 2, :buffers, nil, %{
               generator_state: state,
               output: generator
             })

    assert [
             {:buffer, {:output, [buffer]}},
             {:end_of_stream, :output}
           ] = actions

    assert %Buffer{payload: 1} == buffer
  end
end
