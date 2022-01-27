defmodule Membrane.Testing.EndpointTest do
  use ExUnit.Case

  alias Membrane.Buffer
  alias Membrane.Testing.{Endpoint, Notification}

  test "Endpoint initializes buffer generator and its state properly" do
    generator = fn _state, _size -> nil end

    assert {:ok, %{output: ^generator, generator_state: :abc}} =
             Endpoint.handle_init(%Endpoint{output: {:abc, generator}})
  end

  test "Endpoint sends caps on play" do
    assert {{:ok, caps: {:output, :caps}}, _state} =
             Endpoint.handle_prepared_to_playing(nil, %{caps: :caps})
  end

  describe "Handle write" do
    test "demands when autodemand is true" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {{:ok, actions}, _state} =
               Endpoint.handle_write(:input, buffer, nil, %{autodemand: true})

      assert actions == [
               demand: :input,
               notify: %Notification{payload: {:buffer, buffer}}
             ]
    end

    test "does not demand when autodemand is false" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {{:ok, actions}, _state} =
               Endpoint.handle_write(:input, buffer, nil, %{autodemand: false})

      assert actions == [notify: %Notification{payload: {:buffer, buffer}}]
    end
  end

  describe "Endpoint when handling demand" do
    test "sends next buffer if :output is an enumerable" do
      payloads = Enum.into(1..10, [])
      demand_size = 3

      assert {{:ok, actions}, state} =
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

      assert {{:ok, actions}, _state} =
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

    assert {{:ok, actions}, _state} =
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
