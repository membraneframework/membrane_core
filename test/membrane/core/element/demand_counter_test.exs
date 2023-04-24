defmodule Membrane.Core.Element.DemandCounterTest do
  use ExUnit.Case

  alias Membrane.Core.Element.DemandCounter

  test "if DemandCounter is implemented as :atomics for elements put on the same node" do
    demand_counter = DemandCounter.new(:pull, self(), :buffers, self(), :output)
    :ok = DemandCounter.increase(demand_counter, 10)

    assert get_atomic_value(demand_counter) == 10

    demand_counter = DemandCounter.decrease(demand_counter, 15)

    assert demand_counter.buffered_decrementation == 0
    assert get_atomic_value(demand_counter) == -5
    assert DemandCounter.get(demand_counter) == -5
  end

  test "if DemandCounter.Worker works properly " do
    demand_counter = DemandCounter.new(:pull, self(), :buffers, self(), :output)
    :ok = DemandCounter.increase(demand_counter, 10)

    assert GenServer.call(
             demand_counter.counter.worker,
             {:get, demand_counter.counter.atomic_ref}
           ) == 10

    assert GenServer.call(
             demand_counter.counter.worker,
             {:sub_get, demand_counter.counter.atomic_ref, 15}
           ) == -5

    assert get_atomic_value(demand_counter) == -5

    assert GenServer.call(
             demand_counter.counter.worker,
             {:add_get, demand_counter.counter.atomic_ref, 55}
           ) == 50

    assert get_atomic_value(demand_counter) == 50
    assert DemandCounter.get(demand_counter) == 50
  end

  test "if setting receiver and sender modes works properly" do
    demand_counter = DemandCounter.new(:pull, self(), :buffers, self(), :output)

    :ok = DemandCounter.set_receiver_mode(demand_counter, :push)
    assert DemandCounter.DistributedFlowMode.get(demand_counter.receiver_mode) == :push

    :ok = DemandCounter.set_receiver_mode(demand_counter, :pull)
    assert DemandCounter.DistributedFlowMode.get(demand_counter.receiver_mode) == :pull

    :ok = DemandCounter.set_sender_mode(demand_counter, :push)
    assert DemandCounter.DistributedFlowMode.get(demand_counter.sender_mode) == :push

    :ok = DemandCounter.set_sender_mode(demand_counter, :pull)
    assert DemandCounter.DistributedFlowMode.get(demand_counter.sender_mode) == :pull
  end

  test "if toilet overflows, only and only when it should" do
    hour_in_millis = 60 * 60 * 1000
    sleeping_process = spawn(fn -> Process.sleep(hour_in_millis) end)
    monitor_ref = Process.monitor(sleeping_process)

    demand_counter = DemandCounter.new(:pull, sleeping_process, :buffers, self(), :output)

    :ok = DemandCounter.set_sender_mode(demand_counter, :push)
    demand_counter = DemandCounter.decrease(demand_counter, 100)

    refute_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}

    possible_modes = [:push, :pull, :to_be_resolved]

    demand_counter =
      for mode_1 <- possible_modes, mode_2 <- possible_modes do
        {mode_1, mode_2}
      end
      |> List.delete({:push, :pull})
      |> Enum.reduce(demand_counter, fn {sender_mode, receiver_mode}, demand_counter ->
        :ok = DemandCounter.set_sender_mode(demand_counter, sender_mode)
        :ok = DemandCounter.set_receiver_mode(demand_counter, receiver_mode)
        demand_counter = DemandCounter.decrease(demand_counter, 1000)

        refute_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}

        demand_counter
      end)

    :ok = DemandCounter.set_sender_mode(demand_counter, :push)
    :ok = DemandCounter.set_receiver_mode(demand_counter, :pull)
    _demand_counter = DemandCounter.decrease(demand_counter, 1000)

    assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}
  end

  test "if buffering decrementation works properly with distribution" do
    another_node = setup_another_node()
    pid_on_another_node = Node.spawn(another_node, fn -> :ok end)
    demand_counter = DemandCounter.new(:push, self(), :buffers, pid_on_another_node, :output)

    assert %DemandCounter{buffered_decrementation_limit: 150} = demand_counter

    demand_counter = DemandCounter.decrease(demand_counter, 100)

    assert %DemandCounter{buffered_decrementation: 100} = demand_counter
    assert get_atomic_value(demand_counter) == 0

    demand_counter = DemandCounter.decrease(demand_counter, 49)

    assert %DemandCounter{buffered_decrementation: 149} = demand_counter
    assert get_atomic_value(demand_counter) == 0

    demand_counter = DemandCounter.decrease(demand_counter, 51)

    assert %DemandCounter{buffered_decrementation: 0} = demand_counter
    assert get_atomic_value(demand_counter) == -200
  end

  defp setup_another_node() do
    _cmd_result = System.cmd("epmd", ["-daemon"])
    _start_result = Node.start(:"my_node@127.0.0.1", :longnames)
    {:ok, _pid, another_node} = :peer.start(%{host: ~c"127.0.0.1", name: :another_node})
    :rpc.block_call(another_node, :code, :add_paths, [:code.get_path()])

    on_exit(fn -> :rpc.call(another_node, :init, :stop, []) end)

    another_node
  end

  defp get_atomic_value(demand_counter) do
    demand_counter.counter.atomic_ref
    |> :atomics.get(1)
  end
end
