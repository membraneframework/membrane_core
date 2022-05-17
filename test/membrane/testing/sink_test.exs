defmodule Membrane.Testing.SinkTest do
  use ExUnit.Case

  alias Membrane.Testing.Notification
  alias Membrane.Testing.Sink

  describe "Handle write" do
    test "demands when autodemand is true" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {{:ok, actions}, _state} =
               Sink.handle_write(:input, buffer, nil, %{autodemand: true})

      assert actions == [
               demand: :input,
               notify: %Notification{payload: {:buffer, buffer}}
             ]
    end

    test "does not demand when autodemand is false" do
      buffer = %Membrane.Buffer{payload: 123}

      assert {{:ok, actions}, _state} =
               Sink.handle_write(:input, buffer, nil, %{autodemand: false})

      assert actions == [notify: %Notification{payload: {:buffer, buffer}}]
    end
  end
end
