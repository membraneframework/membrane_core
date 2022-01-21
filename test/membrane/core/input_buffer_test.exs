defmodule Membrane.Core.InputBufferTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.InputBuffer

  test "toilet overflow" do
    [
      fn ->
        toilet(10) |> InputBuffer.store(bufs(11))
      end,
      fn ->
        toilet(10)
        |> InputBuffer.store(bufs(5))
        |> InputBuffer.store(bufs(6))
      end,
      fn ->
        toilet(10)
        |> InputBuffer.store(bufs(8))
        |> InputBuffer.store(bufs(20))
      end
    ]
    |> Enum.each(fn f -> assert_raise RuntimeError, ~r/Toilet overflow.*/, f end)
  end

  test "no toilet overflow" do
    toilet(10) |> InputBuffer.store(bufs(10))
    toilet(10) |> InputBuffer.store(bufs(7)) |> InputBuffer.store(bufs(3))
    assert true
  end

  describe "take_and_demand" do
    setup do
      input_buf = InputBuffer.init(:buffers, self(), :pad, "test", fail_size: 200)
      assert_receive {Membrane.Core.Message, :demand, 40, [for_pad: :pad]}

      [input_buf: input_buf]
    end

    test "returns {:empty, []} when the queue is empty", %{input_buf: input_buf} do
      assert {{:empty, []}, %Membrane.Core.InputBuffer{current_size: 0, demand: 0}} =
               InputBuffer.take_and_demand(input_buf, 1, self(), :input)

      refute_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}
    end

    test "sends demands to the pid and updates demand", %{input_buf: input_buf} do
      assert {{:value, [{:buffers, [1], 1}]}, new_input_buf} =
               input_buf
               |> InputBuffer.store(bufs(10))
               |> InputBuffer.take_and_demand(1, self(), :pad)

      assert_receive {Membrane.Core.Message, :demand, 10, [for_pad: :pad]}

      assert new_input_buf.current_size == 9
      assert new_input_buf.demand == -9
    end
  end

  defp bufs(n), do: Enum.to_list(1..n)

  defp toilet(fail_size) do
    InputBuffer.init(:buffers, self(), :pad, "test", fail_size: fail_size)
    |> InputBuffer.enable_toilet()
  end
end
