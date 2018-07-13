defmodule Membrane.Buffer.Metric.ByteSize do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:bytes` unit
  """

  alias Membrane.Buffer
  alias Membrane.Payload
  @behaviour Buffer.Metric

  def pullbuffer_preferred_size, do: 65_536

  def buffers_size(buffers),
    do: buffers |> Enum.reduce(0, fn %Buffer{payload: p}, acc -> acc + Payload.size(p) end)

  def split_buffers(buffers, count), do: do_split_buffers(buffers, count, [])

  defp do_split_buffers([%Buffer{payload: p} = buf | rest], at_pos, acc) do
    cond do
      at_pos == 0 or rest == [] ->
        {acc |> Enum.reverse(), rest}

      at_pos < Payload.size(p) and at_pos > 0 ->
        {p1, p2} = Payload.split_at(p, at_pos)
        acc = [%Buffer{buf | payload: p1} | acc] |> Enum.reverse()
        rest = [%Buffer{buf | payload: p2} | rest]
        {acc, rest}

      at_pos >= Payload.size(p) ->
        do_split_buffers(rest, at_pos - Payload.size(p), [buf | acc])
    end
  end
end
