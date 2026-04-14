defmodule Membrane.Buffer.Metric.ByteSize do
  @moduledoc """
  Implementation of `Membrane.Buffer.Metric` for the `:bytes` unit.

  > #### Deprecated {: .warning}
  > This module is deprecated. Use `Membrane.Core.Metric` functions with `:bytes` as the
  > `demand_unit` argument instead.
  """

  @behaviour Membrane.Buffer.Metric

  require Membrane.Logger

  alias Membrane.{Buffer, Payload}

  @impl true
  def buffer_size_approximation() do
    ensure_deprecated_warning_printed()
    1500
  end

  @impl true
  def init_manual_demand_size() do
    ensure_deprecated_warning_printed()
    0
  end

  @impl true
  def buffers_size(buffers) do
    ensure_deprecated_warning_printed()

    buffers
    |> Enum.reduce(0, fn %Buffer{payload: p}, acc -> acc + Payload.size(p) end)
    |> then(&{:ok, &1})
  end

  @impl true
  def split_buffers(buffers, count, _first_consumed_buffer, _last_consumed_buffer) do
    ensure_deprecated_warning_printed()
    do_split_buffers(buffers, count, [])
  end

  @impl true
  def reduce_demand(demand, consumed) do
    ensure_deprecated_warning_printed()
    demand - consumed
  end

  defp ensure_deprecated_warning_printed() do
    if Process.get({__MODULE__, :deprecated_warned}) == nil do
      Membrane.Logger.warning(
        "#{__MODULE__} is deprecated. Use Membrane.Core.Metric with :bytes demand_unit instead."
      )

      Process.put({__MODULE__, :deprecated_warned}, true)
    end
  end

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
