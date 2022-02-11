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

  describe "call should" do
    test "return response when receiver process is alive" do
      {:ok, receiver} = GenServer.start_link(Receiver, [])

      response = Message.call(receiver, :request)
      assert response == :ok
    end

    test "return error when receiver process is not alive" do
      Process.flag(:trap_exit, true)
      pid = spawn_link(fn -> :ok end)
      assert_receive {:EXIT, ^pid, :normal}

      response = Message.call(pid, :request, [], [], 500)

      assert match?({:error, {:call_failure, _}}, response)
    end
  end

  describe "call! should" do
    test "return response when receiver process is alive" do
      {:ok, receiver} = GenServer.start_link(Receiver, [])

      response = Message.call!(receiver, :request)
      assert response == :ok
    end

    test "crash when receiver process is not alive" do
      Process.flag(:trap_exit, true)
      pid = spawn_link(fn -> :ok end)
      assert_receive {:EXIT, ^pid, :normal}

      caller_pid =
        spawn_link(fn ->
          Message.call!(pid, :request, [], [], 500)
        end)

      assert_receive {:EXIT, ^caller_pid, {:noproc, _details}}
    end
  end
end
