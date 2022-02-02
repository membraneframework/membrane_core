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
    pid = spawn(fn -> 5 end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    response = Message.call(pid, :request, [], [], 500)

    assert match?({:error, {:call_failure, _}}, response)
  end
end
