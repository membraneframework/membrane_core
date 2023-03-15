defmodule Membrane.Core.Element.ToiletTest do
  use ExUnit.Case
  alias Membrane.Core.Element.Toilet

  setup do
    [responsible_process: spawn(fn -> nil end)]
  end

  test "if toilet is implemented as :atomics for elements put on the same node", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 1, :push, :pull)

    %Toilet{counter: {_pid, atomic_ref}} = toilet

    Toilet.fill(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if the receiving element uses toilet with :atomics and the sending element with a interprocess message, when the toilet is distributed",
       context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 1, :push, :pull)

    %Toilet{counter: {counter_pid, atomic_ref}} = toilet

    Toilet.fill(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 10
    assert :atomics.get(atomic_ref, 1) == 10
    Toilet.drain(toilet, 10)
    assert GenServer.call(counter_pid, {:add_get, atomic_ref, 0}) == 0
    assert :atomics.get(atomic_ref, 1) == 0
  end

  test "if throttling mechanism works properly", context do
    toilet = Toilet.new(100, :buffers, context.responsible_process, 10, :push, :pull)

    {:ok, toilet} = Toilet.fill(toilet, 10)
    assert toilet.unrinsed_buffers_size == 0
    {:ok, toilet} = Toilet.fill(toilet, 5)
    assert toilet.unrinsed_buffers_size == 5
    {:ok, toilet} = Toilet.fill(toilet, 80)
    assert toilet.unrinsed_buffers_size == 0
    {:ok, toilet} = Toilet.fill(toilet, 9)
    assert toilet.unrinsed_buffers_size == 9
    {:overflow, toilet} = Toilet.fill(toilet, 11)
    assert toilet.unrinsed_buffers_size == 0
  end
end
