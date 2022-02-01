defmodule Membrane.Core.MessageTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Message

  require Membrane.Core.Message

  defmodule Receiver do
    use GenServer

    @impl GenServer
    def init(_opts), do: {:ok, nil}

    @impl GenServer
    def handle_call(Message.new(:request), _from, state), do: {:reply, :ok, state}
  end

  test "receiver process alive" do
    {:ok, receiver} = GenServer.start_link(Receiver, [])

    response = Message.call(receiver, :request)

    assert response == :ok
  end

  test "receiver process not alive" do
    response = Message.call(:c.pid(0, 255, 0), :request, [], [], 500)

    assert match?({:error, _reason}, response)
  end
end
