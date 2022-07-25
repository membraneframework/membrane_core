defmodule Membrane.Core.Element.ToiletTest do
  use ExUnit.Case
  alias Membrane.Core.Element.Toilet

  setup do
    [responsible_process: spawn(fn -> nil end)]
  end

  test "if toilet is implemented as :atomics for elements put on the same node", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 1)

    {_module, {_pid, atomic_ref}, _capacity, _responsible_process_pid, _throttling_factor,
     _unrinsed_buffers} = toilet

    Toilet.fill(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if the receiving element uses toilet with :atomics and the sending element with a interprocess message, when the toilet is distributed",
       context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 1)

    {_module, {counter_pid, atomic_ref}, _capacity, _responsible_process_pid, _throttling_factor,
     _unrinsed_buffers} = toilet

    Toilet.fill(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 10
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 0
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if throttling mechanism works properly", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 10)
    {:ok, toilet} = Toilet.fill(toilet, 10)
    assert {_module, _counter, _capacity, _pid, _throttling_factor, 0} = toilet
    {:delay, toilet} = Toilet.fill(toilet, 5)
    assert {_module, _counter, _capacity, _pid, _throttling_factor, 5} = toilet
    {:ok, toilet} = Toilet.fill(toilet, 80)
    assert {_module, _counter, _capacity, _pid, _throttling_factor, 0} = toilet
    {:delay, toilet} = Toilet.fill(toilet, 9)
    assert {_module, _counter, _capacity, _pid, _throttling_factor, 9} = toilet
    {:overflow, toilet} = Toilet.fill(toilet, 11)
    assert {_module, _counter, _capacity, _pid, _throttling_factor, 0} = toilet
  end
end
