defmodule Membrane.Buffer.Metric.Count do
  @moduledoc """
    Implementation of `Membrane.Buffer.Metric` for the `:buffers` unit
  """

  @behaviour Membrane.Buffer.Metric

  @impl true
  def buffer_size_approximation, do: 1

  @impl true
  def buffers_size(buffers), do: length(buffers)

  @impl true
  def split_buffers(buffers, count), do: buffers |> Enum.split(count)
end
