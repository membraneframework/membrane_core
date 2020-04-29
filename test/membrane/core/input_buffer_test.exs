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
    |> Enum.map(fn f -> assert_raise RuntimeError, ~r/Toilet overflow.*/, f end)
  end

  test "no toilet overflow" do
    toilet(10) |> InputBuffer.store(bufs(10))
    toilet(10) |> InputBuffer.store(bufs(7)) |> InputBuffer.store(bufs(3))
    assert true
  end

  defp bufs(n), do: Enum.to_list(1..n)

  defp toilet(fail_size) do
    InputBuffer.init(:buffers, self(), :pad, "test", fail_size: fail_size)
    |> InputBuffer.enable_toilet()
  end
end
