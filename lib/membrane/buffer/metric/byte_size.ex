defmodule Membrane.Buffer.Metric.ByteSize do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:bytes` unit.

  > #### Deprecated {: .warning}
  > This module is deprecated. The metric functionality has been moved to the internal API
  > of the Membrane Framework and is no longer accessible via this behaviour.
  """

  @behaviour Membrane.Buffer.Metric

  alias Membrane.{Buffer, Payload}

  require Membrane.Logger

  @impl true
  def buffer_size_approximation() do
    ensure_deprecated_warning_printed()
    1500
  end

  @impl true
  def buffers_size(buffers) do
    ensure_deprecated_warning_printed()
    Enum.reduce(buffers, 0, fn %Buffer{payload: p}, acc -> acc + Payload.size(p) end)
  end

  @impl true
  def split_buffers(buffers, count) do
    ensure_deprecated_warning_printed()
    do_split_buffers(buffers, count, [])
  end

  defp ensure_deprecated_warning_printed() do
    if Process.get({__MODULE__, :deprecated_warned}) == nil do
      Membrane.Logger.warning("""
      #{__MODULE__} is deprecated. The metric functionality has been moved to the internal \
      API of the Membrane Framework.
      """)

      Process.put({__MODULE__, :deprecated_warned}, true)
    end
  end

  defp do_split_buffers(buffers, at_pos, acc) when at_pos == 0 or buffers == [] do
    {Enum.reverse(acc), buffers}
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
