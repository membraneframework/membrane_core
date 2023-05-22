defmodule Membrane.Core.Element.AtomicDemandTest do
  use ExUnit.Case

  alias Membrane.Core.Element.AtomicDemand
  alias Membrane.Core.SubprocessSupervisor

  test "if AtomicDemand is implemented as :atomics for elements put on the same node" do
    atomic_demand = new_atomic_demand(:pull, self(), self())
    :ok = AtomicDemand.increase(atomic_demand, 10)

    assert get_atomic_value(atomic_demand) == 10

    atomic_demand = AtomicDemand.decrease(atomic_demand, 15)

    assert atomic_demand.buffered_decrementation == 0
    assert get_atomic_value(atomic_demand) == -5
    assert AtomicDemand.get(atomic_demand) == -5
  end

  test "if AtomicDemand.DistributedAtomic.Worker works properly " do
    atomic_demand = new_atomic_demand(:pull, self(), self())
    :ok = AtomicDemand.increase(atomic_demand, 10)

    assert GenServer.call(
             atomic_demand.counter.worker,
             {:get, atomic_demand.counter.atomic_ref}
           ) == 10

    assert GenServer.call(
             atomic_demand.counter.worker,
             {:sub_get, atomic_demand.counter.atomic_ref, 15}
           ) == -5

    assert get_atomic_value(atomic_demand) == -5

    assert GenServer.call(
             atomic_demand.counter.worker,
             {:add_get, atomic_demand.counter.atomic_ref, 55}
           ) == 50

    assert get_atomic_value(atomic_demand) == 50
    assert AtomicDemand.get(atomic_demand) == 50
  end

  test "if setting receiver and sender modes works properly" do
    atomic_demand = new_atomic_demand(:pull, self(), self())

    :ok = AtomicDemand.set_receiver_status(atomic_demand, {:resolved, :push})

    assert AtomicDemand.AtomicFlowStatus.get(atomic_demand.receiver_status) ==
             {:resolved, :push}

    :ok = AtomicDemand.set_receiver_status(atomic_demand, {:resolved, :pull})

    assert AtomicDemand.AtomicFlowStatus.get(atomic_demand.receiver_status) ==
             {:resolved, :pull}

    :ok = AtomicDemand.set_sender_status(atomic_demand, {:resolved, :push})

    assert AtomicDemand.AtomicFlowStatus.get(atomic_demand.sender_status) ==
             {:resolved, :push}

    :ok = AtomicDemand.set_sender_status(atomic_demand, {:resolved, :pull})

    assert AtomicDemand.AtomicFlowStatus.get(atomic_demand.sender_status) ==
             {:resolved, :pull}
  end

  test "if toilet overflows, only and only when it should" do
    hour_in_millis = 60 * 60 * 1000
    sleeping_process = spawn(fn -> Process.sleep(hour_in_millis) end)
    monitor_ref = Process.monitor(sleeping_process)

    atomic_demand = new_atomic_demand(:pull, sleeping_process, self())

    :ok = AtomicDemand.set_sender_status(atomic_demand, {:resolved, :push})
    atomic_demand = AtomicDemand.decrease(atomic_demand, 100)

    refute_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}

    possible_statuses = [{:resolved, :push}, {:resolved, :pull}, :to_be_resolved]

    atomic_demand =
      for status_1 <- possible_statuses, status_2 <- possible_statuses do
        {status_1, status_2}
      end
      |> List.delete({{:resolved, :push}, {:resolved, :pull}})
      |> Enum.reduce(atomic_demand, fn {sender_status, receiver_status}, atomic_demand ->
        :ok = AtomicDemand.set_sender_status(atomic_demand, sender_status)
        :ok = AtomicDemand.set_receiver_status(atomic_demand, receiver_status)
        atomic_demand = AtomicDemand.decrease(atomic_demand, 1000)

        refute_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}

        atomic_demand
      end)

    :ok = AtomicDemand.set_sender_status(atomic_demand, {:resolved, :push})
    :ok = AtomicDemand.set_receiver_status(atomic_demand, {:resolved, :pull})
    _atomic_demand = AtomicDemand.decrease(atomic_demand, 1000)

    assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}
  end

  test "if buffering decrementation works properly with distribution" do
    another_node = setup_another_node()
    pid_on_another_node = Node.spawn(another_node, fn -> :ok end)
    atomic_demand = new_atomic_demand(:push, self(), pid_on_another_node)

    assert %AtomicDemand{throttling_factor: 150} = atomic_demand

    atomic_demand = AtomicDemand.decrease(atomic_demand, 100)

    assert %AtomicDemand{buffered_decrementation: 100} = atomic_demand
    assert get_atomic_value(atomic_demand) == 0

    atomic_demand = AtomicDemand.decrease(atomic_demand, 49)

    assert %AtomicDemand{buffered_decrementation: 149} = atomic_demand
    assert get_atomic_value(atomic_demand) == 0

    atomic_demand = AtomicDemand.decrease(atomic_demand, 51)

    assert %AtomicDemand{buffered_decrementation: 0} = atomic_demand
    assert get_atomic_value(atomic_demand) == -200
  end

  defp setup_another_node() do
    _cmd_result = System.cmd("epmd", ["-daemon"])
    _start_result = Node.start(:"my_node@127.0.0.1", :longnames)
    {:ok, _pid, another_node} = :peer.start(%{host: ~c"127.0.0.1", name: :another_node})
    :rpc.block_call(another_node, :code, :add_paths, [:code.get_path()])

    on_exit(fn -> :rpc.call(another_node, :init, :stop, []) end)

    another_node
  end

  defp get_atomic_value(atomic_demand) do
    atomic_demand.counter.atomic_ref
    |> :atomics.get(1)
  end

  defp new_atomic_demand(receiver_effective_flow_control, receiver_pid, sender_pid) do
    AtomicDemand.new(%{
      receiver_effective_flow_control: receiver_effective_flow_control,
      receiver_process: receiver_pid,
      receiver_demand_unit: :buffers,
      sender_process: sender_pid,
      sender_pad_ref: :output,
      supervisor: SubprocessSupervisor.start_link!()
    })
  end
end
