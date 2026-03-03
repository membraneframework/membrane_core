defmodule Membrane.Buffer.Metric.Count do
  @moduledoc """
    Implementation of `Membrane.Buffer.Metric` for the `:buffers` unit
  """

  @behaviour Membrane.Buffer.Metric

  @impl true
  def buffer_size_approximation(), do: 1

  @impl true
  def init_manual_demand_size_value(), do: 0

  @impl true
  def buffers_size(buffers), do: {:ok, length(buffers)}

  @impl true
  def split_buffers(buffers, count, _first_consumed_buffer, _last_consumed_buffer),
    do: buffers |> Enum.split(count)
end
