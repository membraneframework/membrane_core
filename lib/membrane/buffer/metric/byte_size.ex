defmodule Membrane.Buffer.Metric.ByteSize do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:bytes` unit
  """

  @behaviour Membrane.Buffer.Metric

  alias Membrane.{Buffer, Payload}

  @impl true
  def buffer_size_approximation, do: 1500

  @impl true
  def buffers_size(buffers),
    do: buffers |> Enum.reduce(0, fn %Buffer{payload: p}, acc -> acc + Payload.size(p) end)

  @impl true
  def split_buffers(buffers, count), do: do_split_buffers(buffers, count, [])

  defp do_split_buffers(buffers, at_pos, acc) when at_pos == 0 or buffers == [] do
    {acc |> Enum.reverse(), buffers}
  end

  defp do_split_buffers([%Buffer{payload: p} = buf | rest], at_pos, acc) when at_pos > 0 do
    if at_pos < Payload.size(p) do
      {p1, p2} = Payload.split_at(p, at_pos)
      acc = [%Buffer{buf | payload: p1} | acc] |> Enum.reverse()
      rest = [%Buffer{buf | payload: p2} | rest]
      {acc, rest}
    else
      do_split_buffers(rest, at_pos - Payload.size(p), [buf | acc])
    end
  end
end
