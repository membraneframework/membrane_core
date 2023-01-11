defmodule Membrane.Testing.SinkTest do
  use ExUnit.Case

  alias Membrane.Testing.Notification
  alias Membrane.Testing.Sink

  describe "Handle buffer" do
    test "demands when autodemand is true" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {actions, _state} = Sink.handle_buffer(:input, buffer, nil, %{autodemand: true})

      assert actions == [
               demand: :input,
               notify_parent: %Notification{payload: {:buffer, buffer}}
             ]
    end

    test "does not demand when autodemand is false" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {actions, _state} = Sink.handle_buffer(:input, buffer, nil, %{autodemand: false})

      assert actions == [notify_parent: %Notification{payload: {:buffer, buffer}}]
    end
  end
end
