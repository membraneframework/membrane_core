defmodule Membrane.Core.ToiletTest do
  use ExUnit.Case
  alias Membrane.Core.Element.Toilet

  setup do
    [responsible_process: spawn(fn -> nil end)]
  end

  test "if toilet is implemented as :atomics for elements put on the same node", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, :same_node, 1)

    {_module, {:same_node, atomic_ref}, _capacity, _responsible_process_pid, _throttling_factor} =
      toilet

    Toilet.fill(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if the receiving element uses toilet with :atomics and the sending element with a interprocess message, when the toilet is distributed",
       context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, :different_nodes, 1)

    {_module, {:different_nodes, counter_pid, atomic_ref}, _capacity, _responsible_process_pid,
     _throttling_factor} = toilet

    Toilet.fill(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 10
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 0
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if throttling mechanism works properly", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, :same_node, 10)
    :ok = Toilet.fill(toilet, 10)
    :delay = Toilet.fill(toilet, 5)
    :ok = Toilet.fill(toilet, 90)
    :delay = Toilet.fill(toilet, 9)
    :overflow = Toilet.fill(toilet, 11)
  end
end
