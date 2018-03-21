defmodule Membrane.Buffer.Metric.ByteSize do
  alias Membrane.Buffer
  @behaviour Buffer.Metric

  def pullbuffer_preferred_size, do: 65_536

  def buffers_size(buffers),
    do: buffers |> Enum.reduce(0, fn %Buffer{payload: p}, acc -> acc + byte_size(p) end)

  def split_buffers(buffers, count), do: do_split_buffers_bytes(buffers, count, [])

  defp do_split_buffers_bytes([%Buffer{payload: p} = buf | rest], count, acc)
       when count >= byte_size(p) do
    do_split_buffers_bytes(rest, count - byte_size(p), [buf | acc])
  end

  defp do_split_buffers_bytes([%Buffer{payload: p} = buf | rest], count, acc)
       when count < byte_size(p) and count > 0 do
    <<p1::binary-size(count), p2::binary>> = p
    acc = [%Buffer{buf | payload: p1} | acc] |> Enum.reverse()
    rest = [%Buffer{buf | payload: p2} | rest]
    {acc, rest}
  end

  defp do_split_buffers_bytes(rest, count, acc)
       when count == 0 or rest == [] do
    {acc |> Enum.reverse(), rest}
  end
end
